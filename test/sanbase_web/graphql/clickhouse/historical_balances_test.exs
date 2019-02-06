defmodule SanbaseWeb.Graphql.Clickhouse.HistoricalBalancesTest do
  use SanbaseWeb.ConnCase, async: false

  import SanbaseWeb.Graphql.TestHelpers
  import Mock
  import Sanbase.DateTimeUtils, only: [from_iso8601_to_unix!: 1, from_iso8601!: 1]
  import ExUnit.CaptureLog
  import Sanbase.Factory

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

  test "historical balances when last interval is not full", context do
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
             [from_iso8601_to_unix!("2017-05-18T00:00:00Z"), 1400]
           ]
         }}
      end do
      from = from_iso8601!("2017-05-13T00:00:00Z")
      to = from_iso8601!("2017-05-18T00:00:00Z")
      query = hist_balances_query(context.address, from, to, "2d")

      result =
        context.conn
        |> post("/graphql", query_skeleton(query, "historicalBalance"))

      hist_balance = json_response(result, 200)["data"]["historicalBalance"]

      assert hist_balance == [
               %{"balance" => 2000, "datetime" => "2017-05-13T00:00:00Z"},
               %{"balance" => 1800, "datetime" => "2017-05-15T00:00:00Z"},
               %{"balance" => 1400, "datetime" => "2017-05-17T00:00:00Z"}
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

  test "historical balances when query returns no rows", context do
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

      assert log =~ "clickhouse error"
    end
  end

  test "historical balances with project with contract", context do
    project_with_contract = insert(:project, %{main_contract_address: "0x123"})

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
      query =
        hist_balances_with_slug_query(
          project_with_contract.coinmarketcap_id,
          context.address,
          context.from,
          context.to,
          context.interval
        )

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

  test "historical balances with project without contract", context do
    project_without_contract = insert(:project)

    query =
      hist_balances_with_slug_query(
        project_without_contract.coinmarketcap_id,
        context.address,
        context.from,
        context.to,
        context.interval
      )

    log =
      capture_log(fn ->
        result =
          context.conn
          |> post("/graphql", query_skeleton(query, "historicalBalance"))

        hist_balance = json_response(result, 200)["data"]["historicalBalance"]
        assert hist_balance == []
      end)

    assert log =~ "Can't find contract address"
  end

  defp hist_balances_query(address, from, to, interval) do
    """
      {
        historicalBalance(
            address: "#{address}",
            from: "#{from}",
            to: "#{to}",
            interval: "#{interval}",
            slug: "ethereum"
        ){
            datetime,
            balance
        }
      }
    """
  end

  defp hist_balances_with_slug_query(slug, address, from, to, interval) do
    """
      {
        historicalBalance(
            slug: "#{slug}"
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
