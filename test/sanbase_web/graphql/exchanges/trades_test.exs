defmodule SanbaseWeb.Graphql.Exchanges.TradesTest do
  use SanbaseWeb.ConnCase, async: false

  import SanbaseWeb.Graphql.TestHelpers
  import ExUnit.CaptureLog

  test "#last_exchange_trades", context do
    rows = [
      [1_569_704_025, "Kraken", "ETH/EUR", "buy", 2.11604737, 159.63, 337.7846416731]
    ]

    Sanbase.Mock.prepare_mock2(&Sanbase.ClickhouseRepo.query/2, {:ok, %{rows: rows}})
    |> Sanbase.Mock.run_with_mocks(fn ->
      query = last_trades_query()
      result = execute_query(context.conn, query, "lastExchangeTrades")

      assert hd(result) == expected_exchange_trade()
    end)
  end

  test "#last_exchange_trades with error from clickhouse", context do
    error = "error description"

    Sanbase.Mock.prepare_mock2(&Sanbase.ClickhouseRepo.query/2, {:error, error})
    |> Sanbase.Mock.run_with_mocks(fn ->
      query = last_trades_query()

      log =
        capture_log(fn ->
          execute_query_with_error(context.conn, query, "lastExchangeTrades")
        end)

      assert log =~ inspect(error)

      assert log =~
               ~s(Can't fetch Last exchange trades for exchange and ticker_pair "Kraken" and "ETH/EUR")
    end)
  end

  test "#exchange_trades", context do
    rows = [
      [1_569_704_025, "Kraken", "ETH/EUR", "buy", 2.11604737, 159.63, 337.7846416731]
    ]

    Sanbase.Mock.prepare_mock2(&Sanbase.ClickhouseRepo.query/2, {:ok, %{rows: rows}})
    |> Sanbase.Mock.run_with_mocks(fn ->
      query = trades_query()
      result = execute_query(context.conn, query, "exchangeTrades")

      assert hd(result) == expected_exchange_trade()
    end)
  end

  test "#exchange_trades with error from clickhouse", context do
    error = "error description"

    Sanbase.Mock.prepare_mock2(&Sanbase.ClickhouseRepo.query/2, {:error, error})
    |> Sanbase.Mock.run_with_mocks(fn ->
      query = trades_query()

      log =
        capture_log(fn ->
          execute_query_with_error(context.conn, query, "exchangeTrades")
        end)

      assert log =~ inspect(error)

      assert log =~
               ~s(Can't fetch Exchange trades for exchange and ticker_pair "Kraken" and "ETH/EUR")
    end)
  end

  test "#aggregated exchange_trades", context do
    rows = [
      [1_569_704_025, 2.11604737, 159.63, 337.7846416731, "buy"]
    ]

    Sanbase.Mock.prepare_mock2(&Sanbase.ClickhouseRepo.query/2, {:ok, %{rows: rows}})
    |> Sanbase.Mock.run_with_mocks(fn ->
      query = aggregated_trades_query()
      result = execute_query(context.conn, query, "exchangeTrades")

      assert hd(result) == expected_exchange_trade()
    end)
  end

  test "#aggregated exchange_trades with error from clickhouse", context do
    error = "error description"

    Sanbase.Mock.prepare_mock2(&Sanbase.ClickhouseRepo.query/2, {:error, error})
    |> Sanbase.Mock.run_with_mocks(fn ->
      query = aggregated_trades_query()

      log =
        capture_log(fn ->
          execute_query_with_error(context.conn, query, "exchangeTrades")
        end)

      assert log =~ inspect(error)

      assert log =~
               ~s(Can't fetch Aggregated exchange trades for exchange and ticker_pair "Kraken" and "ETH/EUR")
    end)
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

  defp last_trades_query() do
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

  defp trades_query() do
    """
    {
      exchangeTrades(exchange: "Kraken", tickerPair: "ETH/EUR", from: "2019-10-20T00:00:00Z",  to: "2019-10-21T00:00:00Z") {
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

  defp aggregated_trades_query() do
    """
    {
      exchangeTrades(exchange: "Kraken", tickerPair: "ETH/EUR", from: "2019-10-20T00:00:00Z",  to: "2019-10-21T00:00:00Z", interval: "1d") {
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
