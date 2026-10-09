defmodule SanbaseWeb.Graphql.PriceDataloader do
  alias SanbaseWeb.Graphql.Cache

  require Logger

  @max_concurrency 30

  @doc """
  `Dataloader.KV` batch callback for price-related fields
  (`:volume_change_24h`, `{:price, slug}`, `:last_price_usd`). The
  request `ctx` is threaded into the parallel fan-outs so
  `activity_traces_hidden` masking applies in the spawned workers.
  Returns a map keyed by the batch's entries.
  """
  @spec query(atom() | {:price, String.t()}, term(), Sanbase.RequestContext.t() | nil) :: map()
  def query(:volume_change_24h, args, ctx) do
    slugs = args |> Enum.map(& &1.slug)

    now = Timex.now()
    day_ago = Timex.shift(now, days: -1)
    two_days_ago = Timex.shift(now, days: -2)

    slugs
    |> Enum.chunk_every(100)
    |> Sanbase.Parallel.map(
      fn
        [_ | _] = chunk -> do_volume_change(chunk, now, day_ago, two_days_ago)
        [] -> []
      end,
      max_concurrency: 8,
      # Above the 85s ClickHouse budget and below the 105s Dataloader.KV source
      # timeout. A chunk that still times out is killed and contributes no
      # entries (its slugs resolve to nil) instead of exiting the whole batch.
      # See docs/timeouts.md.
      timeout: 95_000,
      on_timeout: :kill_task,
      zip_input_on_exit: true,
      ordered: false,
      request_context: ctx
    )
    |> Enum.flat_map(fn
      {:exit, {slugs, reason}} ->
        Logger.warning(
          "PriceDataloader :volume_change_24h dropped #{length(slugs)} slugs. Reason: #{inspect(reason)}"
        )

        []

      list ->
        list
    end)
    |> Map.new()
  end

  def query({:price, slug}, ids, ctx) do
    ids
    |> Enum.uniq()
    |> Sanbase.Parallel.map(
      fn id ->
        {id, fetch_price(slug, id)}
      end,
      max_concurrency: @max_concurrency,
      ordered: false,
      request_context: ctx
    )
    |> Map.new()
  end

  def query(:last_price_usd, slugs, _ctx) do
    now = Timex.now()
    yesterday = Timex.shift(Timex.now(), days: -1)
    slugs = Enum.to_list(slugs)

    # Returns result like: {:ok, %{"bitcoin" => 31886.7990282547, "santiment" => 0.07190104}}
    case Sanbase.Metric.aggregated_timeseries_data(
           "price_usd",
           %{slug: slugs},
           yesterday,
           now,
           aggregation: :last
         ) do
      {:ok, result} ->
        result

      # Dataloader.KV stores a per-key error, which `Dataloader.get/4` turns into
      # nil (`get_policy: :return_nil_on_error`); consumers treat nil as "no price".
      {:error, error} ->
        Map.new(slugs, &{&1, {:error, error}})
    end
  end

  # Helper functions

  defp do_volume_change(slugs, latest_dt, middle_dt, earliest_dt) do
    with {:ok, volumes_last_24h_map} <-
           Sanbase.Metric.aggregated_timeseries_data(
             "volume_usd",
             %{slug: slugs},
             middle_dt,
             latest_dt
           ),
         {:ok, volumes_previous_24h_map} <-
           Sanbase.Metric.aggregated_timeseries_data(
             "volume_usd",
             %{slug: slugs},
             earliest_dt,
             middle_dt
           ) do
      calculate_volume_percent_change(volumes_previous_24h_map, volumes_last_24h_map)
    else
      _ ->
        []
    end
  end

  defp calculate_volume_percent_change(previous_map, current_map) do
    current_map
    |> Enum.map(fn {slug, volume} ->
      previous_volume = Map.get(previous_map, slug, 0)

      if is_number(previous_volume) and previous_volume > 1 and is_number(volume) and volume > 1 do
        {slug, Sanbase.Math.percent_change(previous_volume, volume)}
      else
        {slug, nil}
      end
    end)
  end

  defp fetch_price(slug, :last) do
    {:ok, tuple} =
      Cache.wrap(
        fn ->
          now = Timex.now()
          yesterday = Timex.shift(now, days: -1)

          case Sanbase.Price.aggregated_timeseries_data(slug, yesterday, now) do
            {:ok, [%{slug: ^slug, price_usd: price_usd, price_btc: price_btc}]} ->
              {:ok, {price_usd, price_btc}}

            _error ->
              # TODO: Maybe wrap in :nonache tuple
              {:ok, {nil, nil}}
          end
        end,
        :fetch_price_last_record,
        %{slug: slug}
      ).()

    tuple
  end
end
