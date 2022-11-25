defmodule Sanbase.Cryptocompare.CCCAGGPairData do
  alias Sanbase.Project

  require Logger

  def get() do
    cache_key = {__MODULE__, :get_cccagg_pairs_data} |> Sanbase.Cache.hash()

    {:ok, data} =
      Sanbase.Cache.get_or_store(cache_key, fn ->
        data = raw_data() |> pairs_to_maps()
        {:ok, data}
      end)

    data
  end

  def schedule_project_all_time(project_id) do
    with base_asset when is_binary(base_asset) <-
           Project.SourceSlugMapping.get_slug(%Project{id: project_id}, "cryptocompare"),
         [_ | _] = list <- get(),
         %{} = elem <- Enum.find(list, &(&1.base_asset == base_asset)) do
      add_jobs(elem)
    end
  end

  def schedule_oban_jobs() do
    get()
    |> Enum.each(fn elem -> add_jobs(elem) end)
  end

  def schedule_previous_day_oban_jobs() do
    Logger.info("[CCCAGG Pair Data] Start scheduling cryptocompare previous day oban jobs")
    # Make the scrape not just for the previous day, but for a few days before
    # that too. This is to handle some cases where some CSV becoomes available
    # later than we run this code. The uniqueness checkk will handle the overlapping
    # jobs.
    supported_base_assets = supported_base_assets()
    days_ago_7 = Date.utc_today() |> Date.add(-7)
    days_ago_60 = Date.utc_today() |> Date.add(-60)
    today = Date.utc_today()

    list =
      get()
      |> Enum.filter(fn elem ->
        elem.base_asset in supported_base_assets and
          Timex.between?(elem.end_date, days_ago_7, today)
      end)

    Logger.info("[CCCAGG Pair Data] Scheduling oban jobs for #{length(list)} pairs")

    :ok =
      list
      |> Enum.each(fn elem ->
        elem = %{
          start_date: days_ago_60,
          end_date: elem.end_date,
          base_asset: elem.base_asset,
          quote_asset: elem.quote_asset
        }

        add_jobs(elem)
      end)

    Logger.info("[CCCAGG Pair Data] Finished scheduling cryptocompare previous day oban jobs")
  end

  # Private functions

  defp supported_base_assets() do
    Project.SourceSlugMapping.get_source_slug_mappings("cryptocompare")
    |> Enum.map(&elem(&1, 0))
  end

  defp add_jobs(elem) when is_map(elem) do
    Sanbase.Cryptocompare.HistoricalScheduler.add_jobs(
      elem.base_asset,
      elem.quote_asset,
      elem.start_date,
      elem.end_date
    )
  end

  defp pairs_to_maps(pairs) do
    pairs
    |> Enum.flat_map(fn {base_asset, map} ->
      Enum.map(map["tsyms"], fn
        {quote_asset,
         %{"histo_minute_start" => start_date_iso8601, "histo_minute_end" => end_date_iso8601}} ->
          %{
            base_asset: base_asset,
            quote_asset: quote_asset,
            start_date: Date.from_iso8601!(start_date_iso8601),
            end_date: Date.from_iso8601!(end_date_iso8601)
          }

        _ ->
          nil
      end)
      |> Enum.reject(&is_nil/1)
    end)
  end

  defp raw_data() do
    {:ok, %HTTPoison.Response{status_code: 200, body: body}} =
      HTTPoison.get("https://min-api.cryptocompare.com/data/v2/cccagg/pairs")

    body |> Jason.decode!() |> get_in(["Data", "pairs"])
  end
end
