defmodule Sanbase.Cryptocompare.CCCAGGPairData do
  alias Sanbase.Model.Project

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
    # Make the scrape not just for the previous day, but for a few days before
    # that too. This is to handle some cases where some CSV becoomes available
    # later than we run this code. The uniqueness checkk will handle the overlapping
    # jobs.
    days_ago = Date.utc_today() |> Date.add(-3)
    previous_day = Date.utc_today() |> Date.add(-1)

    get()
    |> Enum.filter(fn elem -> elem.end_date == previous_day end)
    |> Enum.map(fn elem ->
      elem = %{
        start_date: days_ago,
        end_date: previous_day,
        base_asset: elem.base_asset,
        quote_asset: elem.quote_asset
      }

      add_jobs(elem)
    end)
  end

  # Private functions

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
      Enum.map(map["tsyms"], fn {quote_asset,
                                 %{
                                   "histo_minute_start" => start_date_iso8601,
                                   "histo_minute_end" => end_date_iso8601
                                 }} ->
        %{
          base_asset: base_asset,
          quote_asset: quote_asset,
          start_date: Date.from_iso8601!(start_date_iso8601),
          end_date: Date.from_iso8601!(end_date_iso8601)
        }
      end)
    end)
  end

  defp raw_data() do
    {:ok, %HTTPoison.Response{status_code: 200, body: body}} =
      HTTPoison.get("https://min-api.cryptocompare.com/data/v2/cccagg/pairs")

    body |> Jason.decode!() |> get_in(["Data", "pairs"])
  end

  defp available_base_assets() do
    # TODO: Remove once all the used assets are scrapped
    # In order to priroritize the jobs that are more important, snooze
    # the jobs that are not having a base asset that is stored in our DBs.
    cache_key = {__MODULE__, :available_base_assets}

    {:ok, assets} =
      Sanbase.Cache.get_or_store(cache_key, fn ->
        data =
          Sanbase.Model.Project.SourceSlugMapping.get_source_slug_mappings("cryptocompare")
          |> Enum.map(&elem(&1, 0))

        {:ok, data}
      end)

    assets
  end
end
