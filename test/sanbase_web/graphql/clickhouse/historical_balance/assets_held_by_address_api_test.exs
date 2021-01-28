defmodule SanbaseWeb.Graphql.Clickhouse.AssetsHeldByAdderssApiTest do
  use SanbaseWeb.ConnCase, async: false

  import Mock
  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers
  import ExUnit.CaptureLog

  alias Sanbase.Clickhouse.HistoricalBalance.EthBalance
  alias Sanbase.Clickhouse.HistoricalBalance.BtcBalance
  alias Sanbase.Clickhouse.HistoricalBalance.Erc20Balance

  setup do
    p1 = insert(:random_erc20_project)
    p2 = insert(:random_erc20_project)

    eth_project = insert(:project, %{name: "Ethereum", slug: "ethereum", ticker: "ETH"})
    btc_project = insert(:project, %{name: "Bitcoin", slug: "bitcoin", ticker: "BTC"})

    insert(:latest_cmc_data, %{coinmarketcap_id: p1.slug, price_usd: 2})
    insert(:latest_cmc_data, %{coinmarketcap_id: p2.slug, price_usd: 2})

    {:ok, [p1: p1, p2: p2, eth_project: eth_project, btc_project: btc_project]}
  end

  test "historical balances returns lists of results for ETH", context do
    %{conn: conn, eth_project: eth_project, p1: p1, p2: p2} = context

    data_erc20 = [
      %{balance: -100.0, slug: p1.slug},
      %{balance: 200.0, slug: p2.slug}
    ]

    data_eth = [%{balance: 1000.0, slug: eth_project.slug}]
    data_metric = %{eth_project.slug => 1300}

    Sanbase.Mock.prepare_mock2(&Erc20Balance.assets_held_by_address/1, {:ok, data_erc20})
    |> Sanbase.Mock.prepare_mock2(&EthBalance.assets_held_by_address/1, {:ok, data_eth})
    |> Sanbase.Mock.prepare_mock2(
      &Sanbase.Metric.aggregated_timeseries_data/5,
      {:ok, data_metric}
    )
    |> Sanbase.Mock.run_with_mocks(fn ->
      query = assets_held_by_address_query("0x123", "ETH")

      result =
        conn
        |> post("/graphql", query_skeleton(query, "assetsHeldByAddress"))
        |> json_response(200)
        |> get_in(["data", "assetsHeldByAddress"])

      assert %{
               "balance" => 200.0,
               "slug" => p2.slug,
               "balanceUsd" => nil
             } in result

      assert %{
               "balance" => 1.0e3,
               "slug" => eth_project.slug,
               "balanceUsd" => 1.0e3 * data_metric[eth_project.slug]
             } in result
    end)
  end

  test "historical balances returns lists of results for BTC", context do
    %{conn: conn, btc_project: btc_project} = context

    data_btc = [%{balance: 200.0, slug: btc_project.slug}]
    data_metric = %{btc_project.slug => 30_000}

    Sanbase.Mock.prepare_mock2(&BtcBalance.assets_held_by_address/1, {:ok, data_btc})
    |> Sanbase.Mock.prepare_mock2(
      &Sanbase.Metric.aggregated_timeseries_data/5,
      {:ok, data_metric}
    )
    |> Sanbase.Mock.run_with_mocks(fn ->
      query = assets_held_by_address_query("0x123", "BTC")

      result =
        conn
        |> post("/graphql", query_skeleton(query, "assetsHeldByAddress"))
        |> json_response(200)

      assert result == %{
               "data" => %{
                 "assetsHeldByAddress" => [
                   %{
                     "balance" => 200.0,
                     "slug" => btc_project.slug,
                     "balanceUsd" => 200 * data_metric[btc_project.slug]
                   }
                 ]
               }
             }
    end)
  end

  test "historical balances results for BTC without timeseries data", context do
    %{conn: conn, btc_project: btc_project} = context

    data_btc = [%{balance: 200.0, slug: btc_project.slug}]

    Sanbase.Mock.prepare_mock2(&BtcBalance.assets_held_by_address/1, {:ok, data_btc})
    |> Sanbase.Mock.prepare_mock2(
      &Sanbase.Metric.aggregated_timeseries_data/5,
      {:ok, %{}}
    )
    |> Sanbase.Mock.run_with_mocks(fn ->
      query = assets_held_by_address_query("0x123", "BTC")

      result =
        conn
        |> post("/graphql", query_skeleton(query, "assetsHeldByAddress"))
        |> json_response(200)

      assert result == %{
               "data" => %{
                 "assetsHeldByAddress" => [
                   %{
                     "balance" => 200.0,
                     "slug" => btc_project.slug,
                     "balanceUsd" => nil
                   }
                 ]
               }
             }
    end)
  end

  test "historical balances returns empty list", context do
    with_mocks [
      {Sanbase.Clickhouse.HistoricalBalance.Erc20Balance, [:passthrough],
       assets_held_by_address: fn _ -> {:ok, []} end},
      {Sanbase.Clickhouse.HistoricalBalance.EthBalance, [:passthrough],
       assets_held_by_address: fn _ -> {:ok, []} end}
    ] do
      address = "0x123"

      query = assets_held_by_address_query(address, "ETH")

      result =
        context.conn
        |> post("/graphql", query_skeleton(query, "assetsHeldByAddress"))
        |> json_response(200)

      assert result == %{"data" => %{"assetsHeldByAddress" => []}}
    end
  end

  test "one of the historical balances returns error", context do
    with_mocks [
      {Sanbase.Clickhouse.HistoricalBalance.Erc20Balance, [:passthrough],
       assets_held_by_address: fn _ ->
         {:ok, []}
       end},
      {Sanbase.Clickhouse.HistoricalBalance.EthBalance, [:passthrough],
       assets_held_by_address: fn _ ->
         {:error, "Something went wrong"}
       end}
    ] do
      address = "0x123"

      query = assets_held_by_address_query(address, "ETH")

      assert capture_log(fn ->
               result =
                 context.conn
                 |> post("/graphql", query_skeleton(query, "assetsHeldByAddress"))
                 |> json_response(200)

               error = result["errors"] |> List.first()

               assert error["message"] =~
                        "Can't fetch Assets held by address for address #{address}"
             end) =~ "Can't fetch Assets held by address for address #{address}"
    end
  end

  test "negative balances are discarded", context do
    with_mocks [
      {Sanbase.Clickhouse.HistoricalBalance.XrpBalance, [:passthrough],
       assets_held_by_address: fn _ ->
         {:ok,
          [
            %{balance: -100.0, slug: context.p1.slug},
            %{balance: -200.0, slug: context.p2.slug}
          ]}
       end},
      {Sanbase.Clickhouse.HistoricalBalance.EthBalance, [:passthrough],
       assets_held_by_address: fn _ ->
         {:ok, [%{balance: -500, slug: context.eth_project.slug}]}
       end}
    ] do
      address = "0x123"

      query = assets_held_by_address_query(address, "XRP")

      result =
        context.conn
        |> post("/graphql", query_skeleton(query, "assetsHeldByAddress"))
        |> json_response(200)

      assert result == %{"data" => %{"assetsHeldByAddress" => []}}
    end
  end

  defp assets_held_by_address_query(address, infrastructure) do
    """
      {
        assetsHeldByAddress(
          selector: {infrastructure: "#{infrastructure}", address: "#{address}"}
        ){
            slug
            balance
            balanceUsd
        }
      }
    """
  end
end
