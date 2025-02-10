defmodule SanbaseWeb.Graphql.Clickhouse.HistoricalBalancesTest do
  use SanbaseWeb.ConnCase, async: false

  import ExUnit.CaptureLog
  import Sanbase.Factory
  import Sanbase.TestHelpers
  import SanbaseWeb.Graphql.TestHelpers

  @moduletag :historical_balance

  setup do
    project_without_contract = insert(:project, %{slug: "someid1", contract_addresses: []})

    project_with_contract =
      insert(:random_erc20_project, %{
        contract_addresses: [build(:contract_address)],
        slug: "someid2",
        token_decimals: 18
      })

    insert(:random_erc20_project, %{slug: "ethereum", ticker: "ETH"})

    [
      project_with_contract: project_with_contract,
      project_without_contract: project_without_contract,
      eth_address: "0x4efb548a2cb8f0af7c591cef21053f6875b5d38f",
      btc_address: "1H9NmjBiMfbNNayVsXshJF8NyQ4FA9TWDT",
      xrp_address: "rwq9nH3qKM3QqFoo6GZSEVCjczSE75v5rc",
      from: ~U[2017-05-11T00:00:00Z],
      to: ~U[2017-05-20T00:00:00Z],
      interval: "1d"
    ]
  end

  test "all infrastructures are supported", context do
    selectors = [
      %{infrastructure: "ETH"},
      %{infrastructure: "ETH", slug: "ethereum"},
      %{infrastructure: "ETH", slug: context.project_with_contract.slug},
      %{infrastructure: "BTC"},
      %{infrastructure: "LTC"},
      %{infrastructure: "BCH"},
      %{infrastructure: "BNB"},
      %{infrastructure: "BNB", slug: "binance-coin"},
      %{infrastructure: "XRP", currency: "XRP", issuer: "XRP"}
    ]

    dt1 = ~U[2019-01-01 00:00:00Z]
    dt2 = ~U[2019-01-02 00:00:00Z]
    dt3 = ~U[2019-01-03 00:00:00Z]
    dt4 = ~U[2019-01-04 00:00:00Z]

    rows = [
      [DateTime.to_unix(dt1), 2000, 1],
      [DateTime.to_unix(dt2), 0, 0],
      [DateTime.to_unix(dt3), 0, 0],
      [DateTime.to_unix(dt4), 1800, 1]
    ]

    (&Sanbase.ClickhouseRepo.query/2)
    |> Sanbase.Mock.prepare_mock2({:ok, %{rows: rows}})
    |> Sanbase.Mock.run_with_mocks(fn ->
      from = dt1
      to = dt4

      for selector <- selectors do
        address =
          case selector.infrastructure do
            "BTC" -> context.btc_address
            "XRP" -> context.xrp_address
            _ -> context.eth_address
          end

        query = historical_balances_query(selector, address, from, to, "1d")

        result =
          context.conn
          |> post("/graphql", query_skeleton(query, "historicalBalance"))
          |> json_response(200)

        refute Map.has_key?(result, "errors")
        assert Map.has_key?(result, "data")

        historical_balance = result["data"]["historicalBalance"]
        assert length(historical_balance) == 4
      end
    end)
  end

  test "historical balances when interval is bigger than balances values interval", context do
    [dt1, dt2, dt3, dt4, dt5, dt6, dt7, dt8, dt9, dt10] =
      ~U[2017-05-11T00:00:00Z]
      |> generate_datetimes("1d", 10)
      |> Enum.map(&DateTime.to_unix/1)

    rows = [
      [dt1, 0, 1],
      [dt2, 0, 1],
      [dt3, 2000, 1],
      [dt4, 1800, 1],
      [dt5, 0, 0],
      [dt6, 1500, 1],
      [dt7, 1900, 1],
      [dt8, 1000, 1],
      [dt9, 0, 0],
      [dt10, 0, 0]
    ]

    (&Sanbase.ClickhouseRepo.query/2)
    |> Sanbase.Mock.prepare_mock2({:ok, %{rows: rows}})
    |> Sanbase.Mock.run_with_mocks(fn ->
      selector = %{infrastructure: "ETH", slug: "ethereum"}

      query =
        historical_balances_query(
          selector,
          context.eth_address,
          context.from,
          context.to,
          context.interval
        )

      result = post(context.conn, "/graphql", query_skeleton(query, "historicalBalance"))

      historical_balance = json_response(result, 200)["data"]["historicalBalance"]

      assert historical_balance == [
               %{"balance" => +0.0, "datetime" => "2017-05-11T00:00:00Z"},
               %{"balance" => +0.0, "datetime" => "2017-05-12T00:00:00Z"},
               %{"balance" => 2000.0, "datetime" => "2017-05-13T00:00:00Z"},
               %{"balance" => 1800.0, "datetime" => "2017-05-14T00:00:00Z"},
               %{"balance" => 1800.0, "datetime" => "2017-05-15T00:00:00Z"},
               %{"balance" => 1500.0, "datetime" => "2017-05-16T00:00:00Z"},
               %{"balance" => 1900.0, "datetime" => "2017-05-17T00:00:00Z"},
               %{"balance" => 1000.0, "datetime" => "2017-05-18T00:00:00Z"},
               %{"balance" => 1000.0, "datetime" => "2017-05-19T00:00:00Z"},
               %{"balance" => 1000.0, "datetime" => "2017-05-20T00:00:00Z"}
             ]
    end)
  end

  test "historical balances when last interval is not full", context do
    [dt1, dt2, dt3] =
      ~U[2017-05-13T00:00:00Z]
      |> generate_datetimes("2d", 3)
      |> Enum.map(&DateTime.to_unix/1)

    rows = [
      [dt1, 2000, 1],
      [dt2, 1800, 1],
      [dt3, 1400, 1]
    ]

    (&Sanbase.ClickhouseRepo.query/2)
    |> Sanbase.Mock.prepare_mock2({:ok, %{rows: rows}})
    |> Sanbase.Mock.run_with_mocks(fn ->
      from = ~U[2017-05-13T00:00:00Z]
      to = ~U[2017-05-18T00:00:00Z]
      selector = %{infrastructure: "ETH", slug: "ethereum"}
      query = historical_balances_query(selector, context.eth_address, from, to, "2d")

      result =
        context.conn
        |> post("/graphql", query_skeleton(query, "historicalBalance"))
        |> json_response(200)

      historical_balance = result["data"]["historicalBalance"]

      assert historical_balance == [
               %{"balance" => 2000.0, "datetime" => "2017-05-13T00:00:00Z"},
               %{"balance" => 1800.0, "datetime" => "2017-05-15T00:00:00Z"},
               %{"balance" => 1400.0, "datetime" => "2017-05-17T00:00:00Z"}
             ]
    end)
  end

  test "historical balances when query returns error", context do
    error = "Something went wrong"

    (&Sanbase.ClickhouseRepo.query/2)
    |> Sanbase.Mock.prepare_mock2({:error, error})
    |> Sanbase.Mock.run_with_mocks(fn ->
      selector = %{infrastructure: "ETH", slug: "ethereum"}

      query =
        historical_balances_query(
          selector,
          context.eth_address,
          context.from,
          context.to,
          context.interval
        )

      log =
        capture_log(fn ->
          result =
            context.conn
            |> post("/graphql", query_skeleton(query, "historicalBalance"))
            |> json_response(200)

          historical_balance = result["data"]["historicalBalance"]
          assert historical_balance == nil
        end)

      assert log =~ error

      assert log =~
               ~s|Can't fetch Historical Balances for selector #{inspect(selector)}|
    end)
  end

  test "historical balances when query returns no rows", context do
    (&Sanbase.ClickhouseRepo.query/2)
    |> Sanbase.Mock.prepare_mock2({:ok, %{rows: []}})
    |> Sanbase.Mock.run_with_mocks(fn ->
      selector = %{infrastructure: "ETH", slug: "ethereum"}

      query =
        historical_balances_query(
          selector,
          context.eth_address,
          context.from,
          context.to,
          context.interval
        )

      result = post(context.conn, "/graphql", query_skeleton(query, "historicalBalance"))

      historical_balance = json_response(result, 200)["data"]["historicalBalance"]
      assert historical_balance == []
    end)
  end

  test "historical balances with project with contract", context do
    [dt1, dt2, dt3, dt4, dt5, dt6, dt7, dt8, dt9, dt10] =
      ~U[2017-05-11T00:00:00Z]
      |> generate_datetimes("1d", 10)
      |> Enum.map(&DateTime.to_unix/1)

    rows = [
      [dt1, 0, 1],
      [dt2, 0, 1],
      [dt3, 2000, 1],
      [dt4, 1800, 1],
      [dt5, 0, 0],
      [dt6, 1500, 1],
      [dt7, 1900, 1],
      [dt8, 1000, 1],
      [dt9, 0, 0],
      [dt10, 0, 0]
    ]

    (&Sanbase.ClickhouseRepo.query/2)
    |> Sanbase.Mock.prepare_mock2({:ok, %{rows: rows}})
    |> Sanbase.Mock.run_with_mocks(fn ->
      selector = %{infrastructure: "ETH", slug: context.project_with_contract.slug}

      query =
        historical_balances_query(
          selector,
          context.eth_address,
          context.from,
          context.to,
          context.interval
        )

      result =
        context.conn
        |> post("/graphql", query_skeleton(query, "historicalBalance"))
        |> json_response(200)

      historical_balance = result["data"]["historicalBalance"]

      assert historical_balance == [
               %{"balance" => +0.0, "datetime" => "2017-05-11T00:00:00Z"},
               %{"balance" => +0.0, "datetime" => "2017-05-12T00:00:00Z"},
               %{"balance" => 2000.0, "datetime" => "2017-05-13T00:00:00Z"},
               %{"balance" => 1800.0, "datetime" => "2017-05-14T00:00:00Z"},
               %{"balance" => 1800.0, "datetime" => "2017-05-15T00:00:00Z"},
               %{"balance" => 1500.0, "datetime" => "2017-05-16T00:00:00Z"},
               %{"balance" => 1900.0, "datetime" => "2017-05-17T00:00:00Z"},
               %{"balance" => 1000.0, "datetime" => "2017-05-18T00:00:00Z"},
               %{"balance" => 1000.0, "datetime" => "2017-05-19T00:00:00Z"},
               %{"balance" => 1000.0, "datetime" => "2017-05-20T00:00:00Z"}
             ]
    end)
  end

  test "historical balances with project without contract", context do
    selector = %{infrastructure: "ETH", slug: context.project_without_contract.slug}

    query =
      historical_balances_query(
        selector,
        context.eth_address,
        context.from,
        context.to,
        context.interval
      )

    log =
      capture_log(fn ->
        result =
          context.conn
          |> post("/graphql", query_skeleton(query, "historicalBalance"))
          |> json_response(200)

        historical_balance = result["data"]["historicalBalance"]
        assert historical_balance == nil

        error = List.first(result["errors"])

        assert error["message"] =~
                 "Can't fetch Historical Balances for selector #{inspect(selector)}"
      end)

    assert log =~ "Can't find contract address or infrastructure of project with slug: someid1"
  end

  test "historical balances when clickhouse returns error", context do
    error = "Something bad happened"

    (&Sanbase.ClickhouseRepo.query/2)
    |> Sanbase.Mock.prepare_mock2({:error, error})
    |> Sanbase.Mock.run_with_mocks(fn ->
      selector = %{infrastructure: "ETH", slug: context.project_with_contract.slug}

      query =
        historical_balances_query(
          selector,
          context.eth_address,
          context.from,
          context.to,
          context.interval
        )

      log =
        capture_log(fn ->
          result =
            context.conn
            |> post("/graphql", query_skeleton(query, "historicalBalance"))
            |> json_response(200)

          error = List.first(result["errors"])

          assert error["message"] =~
                   "Can't fetch Historical Balances for selector #{inspect(selector)}"
        end)

      assert log =~ "Can't fetch Historical Balances for selector"
    end)
  end

  defp historical_balances_query(selector, address, from, to, interval) do
    selector_json = Enum.map_join(selector, ", ", fn {k, v} -> ~s/#{k}: "#{v}"/ end)
    selector_json = "{" <> selector_json <> "}"

    """
      {
        historicalBalance(
            selector: #{selector_json}
            address: "#{address}"
            from: "#{from}"
            to: "#{to}"
            interval: "#{interval}"
        ){
            datetime
            balance
        }
      }
    """
  end
end
