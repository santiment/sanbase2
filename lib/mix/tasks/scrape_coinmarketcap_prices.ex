defmodule Mix.Tasks.ScrapeCoinmarketcapPrices do
  use Mix.Task

  @shortdoc "Scrapes 5 min prices from coinmarketcap"

  alias Sanbase.ExternalServices.Coinmarketmap.GraphData
  alias Sanbase.Prices.Store

  def run([token, start_time, end_time]) do
    {:ok, _started} = Application.ensure_all_started(:sanbase)

    GraphData.fetch_prices(
      token,
      parse_date(start_time, 0, 0, 0),
      parse_date(end_time, 23, 59, 59)
    )
    |> Store.import_price_points("#{token}_USD", source: "coinmarketcap")
  end

  defp parse_date(date, hour, min, sec) do
    parsed_date = date
    |> Date.from_iso8601!

    {:ok, naive_datetime} = NaiveDateTime.new(
      parsed_date.year,
      parsed_date.month,
      parsed_date.day,
      hour, min, sec)

    DateTime.from_naive!(naive_datetime, "Etc/UTC")
  end
end
