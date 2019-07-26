defmodule Sanbase.ExternalServices.Coinmarketcap.TickerFetcherTest do
  use ExUnit.Case
  use Sanbase.DataCase, async: false

  # TODO: Change after old cmc scraper is removed
  alias Sanbase.ExternalServices.Coinmarketcap.TickerFetcher2, as: TickerFetcher
  alias Sanbase.Prices.Store

  import Sanbase.InfluxdbHelpers

  @btc_measurement "BTC_bitcoin"
  @eth_measurement "ETH_ethereum"

  test "parsing the project page" do
    IO.inspect("#{Timex.now()} BEGIN TEST")
    setup_prices_influxdb()

    IO.inspect("",
      label:
        "#{Timex.now()} message; #{
          String.replace_leading("#{__ENV__.file}", "#{File.cwd!()}", "") |> Path.relative()
        }:#{__ENV__.line()}"
    )

    Tesla.Mock.mock(fn %{method: :get} ->
      %Tesla.Env{status: 200, body: File.read!(Path.join(__DIR__, "pro_cmc_api_2.json"))}
    end)

    IO.inspect("BEFORE WORK",
      label:
        "#{Timex.now()} message; #{
          String.replace_leading("#{__ENV__.file}", "#{File.cwd!()}", "") |> Path.relative()
        }:#{__ENV__.line()}"
    )

    TickerFetcher.work()

    IO.inspect("AFTER WORK",
      label:
        "#{Timex.now()} message; #{
          String.replace_leading("#{__ENV__.file}", "#{File.cwd!()}", "") |> Path.relative()
        }:#{__ENV__.line()}"
    )

    from = DateTime.from_naive!(~N[2018-08-17 08:35:00], "Etc/UTC")
    to = DateTime.from_naive!(~N[2018-08-17 10:40:00], "Etc/UTC")

    # Test bitcoin is in influx
    assert Store.fetch_price_points!(@btc_measurement, from, to) == [
             [
               DateTime.from_naive!(~N[2018-08-17 08:55:37], "Etc/UTC"),
               6493.02288075,
               1,
               111_774_707_274,
               4_858_871_494
             ]
           ]

    # Test Ethereum is in influx
    assert Store.fetch_price_points!(@eth_measurement, from, to) == [
             [
               DateTime.from_naive!(~N[2018-08-17 08:54:55], "Etc/UTC"),
               300.96820061,
               0.04633099381624731,
               30_511_368_440,
               1_689_698_769
             ]
           ]
  end
end
