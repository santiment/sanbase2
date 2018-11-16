defmodule SanbaseWeb.Graphql.Clickhouse.HistoricalBalancesTest do
  use SanbaseWeb.ConnCase, async: false

  import SanbaseWeb.Graphql.TestHelpers
  import Mock
  import Sanbase.DateTimeUtils, only: [from_iso8601_to_unix!: 1, from_iso8601!: 1]
  import ExUnit.CaptureLog

  require Sanbase.ClickhouseRepo

  setup do
    [
      address: "0x321321321",
      from: from_iso8601!("2017-05-11T00:00:00Z"),
      to: from_iso8601!("2017-05-20T00:00:00Z"),
      interval: "1d"
    ]
  end

  test "historical balances when interval is bigger than balances values interval", context do
    with_mock Sanbase.ClickhouseRepo,
      query: fn _, _ ->
        {:ok,
         %{
           rows: [
             [from_iso8601_to_unix!("2017-05-13T00:00:00Z"), 2000],
             [from_iso8601_to_unix!("2017-05-14T00:00:00Z"), 1800],
             [from_iso8601_to_unix!("2017-05-15T00:00:00Z"), 1800],
             [from_iso8601_to_unix!("2017-05-16T00:00:00Z"), 1500],
             [from_iso8601_to_unix!("2017-05-17T00:00:00Z"), 1900],
             [from_iso8601_to_unix!("2017-05-18T00:00:00Z"), 1000]
           ]
         }}
      end do
      query = hist_balances_query(context.address, context.from, context.to, context.interval)

      result =
        context.conn
        |> post("/graphql", query_skeleton(query, "historicalBalance"))

      hist_balance = json_response(result, 200)["data"]["historicalBalance"]

      assert hist_balance == [
               %{"balance" => 0, "datetime" => "2017-05-11T00:00:00Z"},
               %{"balance" => 0, "datetime" => "2017-05-12T00:00:00Z"},
               %{"balance" => 2000, "datetime" => "2017-05-13T00:00:00Z"},
               %{"balance" => 1800, "datetime" => "2017-05-14T00:00:00Z"},
               %{"balance" => 1800, "datetime" => "2017-05-15T00:00:00Z"},
               %{"balance" => 1500, "datetime" => "2017-05-16T00:00:00Z"},
               %{"balance" => 1900, "datetime" => "2017-05-17T00:00:00Z"},
               %{"balance" => 1000, "datetime" => "2017-05-18T00:00:00Z"},
               %{"balance" => 1000, "datetime" => "2017-05-19T00:00:00Z"},
               %{"balance" => 1000, "datetime" => "2017-05-20T00:00:00Z"}
             ]
    end
  end

  test "historical balances when interval is inner to the balances values", context do
    with_mock Sanbase.ClickhouseRepo,
      query: fn _, _ ->
        {:ok,
         %{
           rows: [
             [from_iso8601_to_unix!("2017-05-13T00:00:00Z"), 2000],
             [from_iso8601_to_unix!("2017-05-14T00:00:00Z"), 1800],
             [from_iso8601_to_unix!("2017-05-15T00:00:00Z"), 1800],
             [from_iso8601_to_unix!("2017-05-16T00:00:00Z"), 1500],
             [from_iso8601_to_unix!("2017-05-17T00:00:00Z"), 1900],
             [from_iso8601_to_unix!("2017-05-18T00:00:00Z"), 1000]
           ]
         }}
      end do
      from = from_iso8601!("2017-05-15T00:00:00Z")
      to = from_iso8601!("2017-05-17T00:00:00Z")
      query = hist_balances_query(context.address, from, to, context.interval)

      result =
        context.conn
        |> post("/graphql", query_skeleton(query, "historicalBalance"))

      hist_balance = json_response(result, 200)["data"]["historicalBalance"]

      assert hist_balance == [
               %{"balance" => 1800, "datetime" => "2017-05-15T00:00:00Z"},
               %{"balance" => 1500, "datetime" => "2017-05-16T00:00:00Z"},
               %{"balance" => 1900, "datetime" => "2017-05-17T00:00:00Z"}
             ]
    end
  end

  test "historical balances when query returns error", context do
    with_mock Sanbase.ClickhouseRepo, query: fn _, _ -> {:error, :invalid} end do
      query = hist_balances_query(context.address, context.from, context.to, context.interval)

      result =
        context.conn
        |> post("/graphql", query_skeleton(query, "historicalBalance"))

      hist_balance = json_response(result, 200)["data"]["historicalBalance"]
      assert hist_balance == []
    end
  end

  test "historical balances when query returns not rows", context do
    with_mock Sanbase.ClickhouseRepo, query: fn _, _ -> {:ok, %{rows: []}} end do
      query = hist_balances_query(context.address, context.from, context.to, context.interval)

      result =
        context.conn
        |> post("/graphql", query_skeleton(query, "historicalBalance"))

      hist_balance = json_response(result, 200)["data"]["historicalBalance"]
      assert hist_balance == []
    end
  end

  test "when interval is smaller than 1hr returns error", context do
    query = hist_balances_query(context.address, context.from, context.to, "20m")

    result =
      context.conn
      |> post("/graphql", query_skeleton(query, "historicalBalance"))

    [error | _] = json_response(result, 200)["errors"]
    assert String.contains?(error["message"], "Interval must be bigger than 1 hour")
  end

  test "historical balances when query raises", context do
    with_mock Sanbase.ClickhouseRepo, query: fn _, _ -> raise("clickhouse error") end do
      query = hist_balances_query(context.address, context.from, context.to, context.interval)

      log =
        capture_log(fn ->
          result =
            context.conn
            |> post("/graphql", query_skeleton(query, "historicalBalance"))

          hist_balance = json_response(result, 200)["data"]["historicalBalance"]
          assert hist_balance == []
        end)

      assert log =~
               ~s([error] Exception raised while calculating historical balances for 0x321321321. Reason: %RuntimeError{message: "clickhouse error"})
    end
  end

  defp hist_balances_query(address, from, to, interval) do
    """
      {
        historicalBalance(
            address: "#{address}",
            from: "#{from}",
            to: "#{to}",
            interval: "#{interval}"
        ){
            datetime,
            balance
        }
      }
    """
  end
end
