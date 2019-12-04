defmodule SanbaseWeb.Graphql.Exchanges.MarketDepthTest do
  use SanbaseWeb.ConnCase

  import Mock
  import SanbaseWeb.Graphql.TestHelpers
  import ExUnit.CaptureLog

  test "#last_market_depth", context do
    with_mock(Sanbase.ClickhouseRepo,
      query: fn _, _ ->
        {:ok,
         %{
           rows: [result_row()]
         }}
      end
    ) do
      query = last_market_depth_query()
      result = execute_query(context.conn, query, "lastExchangeMarketDepth")

      assert hd(result) == expected_exchange_market_depth()
    end
  end

  test "#last_market_depth with error from clickhouse", context do
    error = "error description"

    with_mock(Sanbase.ClickhouseRepo,
      query: fn _, _ ->
        {:error, error}
      end
    ) do
      query = last_market_depth_query()

      log =
        capture_log(fn ->
          execute_query_with_error(context.conn, query, "lastExchangeMarketDepth")
        end)

      assert log =~
               ~s(Can't fetch Last exchange market depth for exchange and ticker_pair: "Kraken" and "ZEC/BTC", Reason: #{
                 inspect(error)
               })
    end
  end

  defp expected_exchange_market_depth() do
    %{
      "ask" => 0.00455979,
      "asks025PercentDepth" => 0.0012996121796948,
      "asks025PercentVolume" => 0.28495291,
      "bid" => 0.00455005,
      "bids025PercentDepth" => 0.7868672411467281,
      "bids025PercentVolume" => 173.00153222999998,
      "exchange" => "Kraken",
      "tickerPair" => "ZEC/BTC",
      "datetime" => "2019-10-18T16:50:28Z"
    }
  end

  defp last_market_depth_query() do
    """
    {
      lastExchangeMarketDepth(exchange: "Kraken", tickerPair: "ZEC/BTC") {
        exchange
        tickerPair
        datetime
        ask
        bid
        asks025PercentDepth
        asks025PercentVolume
        bids025PercentDepth
        bids025PercentVolume
      }
    }
    """
  end

  defp result_row() do
    [
      1_571_417_428,
      "Kraken",
      "ZEC/BTC",
      0.00455979,
      0.0012996121796948,
      0.28495291,
      nil,
      nil,
      nil,
      nil,
      nil,
      nil,
      nil,
      nil,
      nil,
      nil,
      nil,
      nil,
      nil,
      nil,
      nil,
      nil,
      0.00455005,
      0.7868672411467281,
      173.00153222999998,
      nil,
      nil,
      nil,
      nil,
      nil,
      nil,
      nil,
      nil,
      nil,
      nil,
      nil,
      nil,
      nil,
      nil,
      nil,
      nil
    ]
  end
end
