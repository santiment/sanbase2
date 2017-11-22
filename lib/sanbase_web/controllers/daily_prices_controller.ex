defmodule SanbaseWeb.DailyPricesController do
  use SanbaseWeb, :controller

  alias Sanbase.Prices.Store

  import Sanbase.DateTimeUtils, only: [seconds_ago: 1]

  @days_limit 14 * 24 * 60 * 60 # 14 days
  @pairs [
    "BTC_USD",
    "ETH_USD",
    "BCH_USD",
    "XRP_USD",
    "DASH_USD",
    "LTC_USD",
    "MIOTA_USD",
    "NEO_USD",
    "XMR_USD",
    "XEM_USD",
    "ETC_USD",
    "LSK_USD",
    "QTUM_USD",
    "EOS_USD",
    "OMG_USD",
    "ZEC_USD",
    "ADA_USD",
    "HSR_USD",
    "XLM_USD",
    "USDT_USD"
  ]

  def index(conn, _params) do
    prices = @pairs
    |> Enum.reduce(%{}, fn pair, acc ->
      acc
      |> Map.put(pair, Store.fetch_prices_with_resolution(pair, seconds_ago(@days_limit), DateTime.utc_now(), "1d"))
    end)

    render conn, "index.json", prices: prices
  end
end
