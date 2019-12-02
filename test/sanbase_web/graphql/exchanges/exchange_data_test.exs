defmodule SanbaseWeb.Graphql.Exchanges.TradesTest do
  use SanbaseWeb.ConnCase

  import Mock
  import SanbaseWeb.Graphql.TestHelpers

  alias Sanbase.Clickhouse.Exchanges.Trades

  test "#last_exchange_trades", context do
    with_mock(Sanbase.ClickhouseRepo,
      query: fn _, _ ->
        {:ok,
         %{
           rows: [
             ["Kraken", "ETH/EUR", 1_569_704_025, "buy", 2.11604737, 159.63, 337.7846416731]
           ]
         }}
      end
    ) do
      query = trades_query()
      result = execute_query(context.conn, query, "lastExchangeTrades")

      assert hd(result) == expected_exchange_trade()
    end
  end

  defp expected_exchange_trade() do
    %{
      "amount" => 2.11604737,
      "cost" => 337.7846416731,
      "price" => 159.63,
      "exchange" => "Kraken",
      "tickerPair" => "ETH/EUR",
      "datetime" => "2019-09-28T20:53:45Z"
    }
  end

  defp trades_query() do
    """
    {
      lastExchangeTrades(exchange: "Kraken", tickerPair: "ETH/EUR") {
        exchange
        tickerPair
        datetime
        amount
        price
        cost
      }
    }
    """
  end
end
