defmodule SanbaseWeb.Graphql.PriceDataloader do
  alias SanbaseWeb.Graphql.Cache

  require Logger

  @max_concurrency 30

  def data() do
    Dataloader.KV.new(&query/2)
  end

  def query(:volume_change_24h, args) do
    slugs = args |> Enum.map(& &1.slug)

    now = Timex.now()
    day_ago = Timex.shift(now, days: -1)
    two_days_ago = Timex.shift(now, days: -2)

    slugs
    |> Enum.chunk_every(100)
    |> Sanbase.Parallel.flat_map(
      fn
        [_ | _] = chunk -> do_volume_change(chunk, now, day_ago, two_days_ago)
        [] -> []
      end,
      max_concurrency: 8,
      ordered: false
    )
    |> Map.new()
  end

  def query({:price, slug}, ids) do
    ids
    |> Enum.uniq()
    |> Sanbase.Parallel.map(
      fn id ->
        {id, fetch_price(slug, id)}
      end,
      max_concurrency: @max_concurrency,
      ordered: false
    )
    |> Map.new()
  end

  def query(:last_price_usd, slugs) do
    now = Timex.now()
    yesterday = Timex.shift(Timex.now(), days: -1)
    slugs = Enum.to_list(slugs)

    # Returns result like: {:ok, %{"bitcoin" => 31886.7990282547, "santiment" => 0.07190104}}
    {:ok, result} =
      Sanbase.Metric.aggregated_timeseries_data(
        "price_usd",
        %{slug: slugs},
        yesterday,
        now,
        aggregation: :last
      )

    result
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
    Cache.wrap(
      fn ->
        now = Timex.now()
        yesterday = Timex.shift(now, days: -1)

        case Sanbase.Price.aggregated_timeseries_data(slug, yesterday, now) do
          {:ok, [%{slug: ^slug, price_usd: price_usd, price_btc: price_btc}]} ->
            {price_usd, price_btc}

          _error ->
            {nil, nil}
        end
      end,
      :fetch_price_last_record,
      %{slug: slug}
    ).()
  end
end
