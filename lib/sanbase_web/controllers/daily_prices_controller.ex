defmodule SanbaseWeb.DailyPricesController do
  use SanbaseWeb, :controller

  alias Sanbase.Prices.Store

  import Sanbase.DateTimeUtils, only: [seconds_ago: 1]

  # 14 days
  @days_limit 14 * 24 * 60 * 60
  @max_assets_to_return 20

  def index(conn, %{"tickers" => tickers}) do
    prices =
      String.split(tickers, ",")
      |> Enum.map(&String.trim/1)
      |> Enum.take(@max_assets_to_return)
      |> Enum.map(fn ticker -> "#{ticker}_USD" end)
      |> Enum.reduce(%{}, fn pair, acc ->
        acc
        |> Map.put(
          pair,
          Store.fetch_prices_with_resolution(
            pair,
            seconds_ago(@days_limit),
            DateTime.utc_now(),
            "1d"
          )
        )
      end)

    render(conn, "index.json", prices: prices)
  end
end
