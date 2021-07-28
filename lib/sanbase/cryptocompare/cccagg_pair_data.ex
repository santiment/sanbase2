defmodule Sanbase.Cryptocompare.CCCAGGPairData do
  def get() do
    raw_data() |> pairs_to_maps()
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

  def schedule_oban_jobs() do
    get()
    |> Enum.each(fn elem ->
      Sanbase.Cryptocompare.HistoricalScheduler.add_jobs(
        elem.base_asset,
        elem.quote_asset,
        elem.start_date,
        elem.end_date
      )
    end)
  end

  defp raw_data() do
    {:ok, %HTTPoison.Response{status_code: 200, body: body}} =
      HTTPoison.get("https://min-api.cryptocompare.com/data/v2/cccagg/pairs")

    body |> Jason.decode!() |> get_in(["Data", "pairs"])
  end
end
