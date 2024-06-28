defmodule SanbaseWeb.Graphql.Clickhouse.AssetsHeldByAdderssApiTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  @moduletag :historical_balance

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

    data = [
      %{balance: -100.0, slug: p1.slug},
      %{balance: 200.0, slug: p2.slug},
      %{balance: 1000.0, slug: eth_project.slug}
    ]

    ethereum_usd_price = 1300

    Sanbase.Mock.prepare_mock2(&Sanbase.Balance.assets_held_by_address/2, {:ok, data})
    |> Sanbase.Mock.prepare_mock2(
      &Sanbase.Metric.aggregated_timeseries_data/5,
      # Ethereum's price usd
      {:ok, %{eth_project.slug => ethereum_usd_price}}
    )
    |> Sanbase.Mock.run_with_mocks(fn ->
      query = assets_held_by_address_query("0x4efb548a2cb8f0af7c591cef21053f6875b5d38f", "ETH")

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
               "balanceUsd" => 1.0e3 * ethereum_usd_price
             } in result
    end)
  end

  test "historical balances returns lists of results for BTC", context do
    %{conn: conn, btc_project: btc_project} = context

    bitcoin_usd_price = 30_000
    data_btc = [%{balance: 200.0, slug: btc_project.slug}]

    Sanbase.Mock.prepare_mock2(&Sanbase.Balance.assets_held_by_address/2, {:ok, data_btc})
    |> Sanbase.Mock.prepare_mock2(
      &Sanbase.Metric.aggregated_timeseries_data/5,
      # Bitcoin's price in usd
      {:ok, %{btc_project.slug => bitcoin_usd_price}}
    )
    |> Sanbase.Mock.run_with_mocks(fn ->
      query = assets_held_by_address_query("0x4efb548a2cb8f0af7c591cef21053f6875b5d38f", "BTC")

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
                     "balanceUsd" => 200.0 * bitcoin_usd_price
                   }
                 ]
               }
             }
    end)
  end

  test "historical balances results for BTC without timeseries data", context do
    %{conn: conn, btc_project: btc_project} = context

    data_btc = [%{balance: 200.0, slug: btc_project.slug}]

    Sanbase.Mock.prepare_mock2(&Sanbase.Balance.assets_held_by_address/2, {:ok, data_btc})
    |> Sanbase.Mock.prepare_mock2(&Sanbase.Metric.aggregated_timeseries_data/5, {:ok, %{}})
    |> Sanbase.Mock.run_with_mocks(fn ->
      query = assets_held_by_address_query("0x4efb548a2cb8f0af7c591cef21053f6875b5d38f", "BTC")

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
    Sanbase.Mock.prepare_mock2(&Sanbase.Balance.assets_held_by_address/2, {:ok, []})
    |> Sanbase.Mock.run_with_mocks(fn ->
      address = "0x4efb548a2cb8f0af7c591cef21053f6875b5d38f"

      query = assets_held_by_address_query(address, "ETH")

      result =
        context.conn
        |> post("/graphql", query_skeleton(query, "assetsHeldByAddress"))
        |> json_response(200)

      assert result == %{"data" => %{"assetsHeldByAddress" => []}}
    end)
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
