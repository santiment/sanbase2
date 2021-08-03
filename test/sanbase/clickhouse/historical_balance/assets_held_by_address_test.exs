defmodule Sanbase.Clickhouse.HistoricalBalance.AssetsHeldByAdderssTest do
  use Sanbase.DataCase

  import Sanbase.Factory

  alias Sanbase.Clickhouse.HistoricalBalance

  @moduletag :historical_balance

  setup do
    p1 = insert(:random_erc20_project)
    p2 = insert(:random_erc20_project)

    eth_project =
      insert(:project, %{
        name: "Ethereum",
        slug: "ethereum",
        coinmarketcap_id: "ethereum",
        ticker: "ETH"
      })

    insert(:latest_cmc_data, %{coinmarketcap_id: p1.slug, price_usd: 2})
    insert(:latest_cmc_data, %{coinmarketcap_id: p2.slug, price_usd: 2})
    insert(:latest_cmc_data, %{coinmarketcap_id: eth_project.slug, price_usd: 2})

    {:ok, [p1: p1, p2: p2, eth_project: eth_project]}
  end

  test "clickhouse returns list of results", context do
    Sanbase.Mock.prepare_mock2(
      &Sanbase.Balance.assets_held_by_address/1,
      {:ok,
       [
         %{balance: 1000.0, slug: context.eth_project.slug},
         %{balance: 100.0, slug: context.p1.slug},
         %{balance: 200.0, slug: context.p2.slug}
       ]}
    )
    |> Sanbase.Mock.run_with_mocks(fn ->
      assert HistoricalBalance.assets_held_by_address(%{address: "0x123", infrastructure: "ETH"}) ==
               {:ok,
                [
                  %{slug: context.eth_project.slug, balance: 1000.0},
                  %{slug: context.p2.slug, balance: 200.0},
                  %{slug: context.p1.slug, balance: 100.0}
                ]}
    end)
  end

  test "clickhouse returns no results", _context do
    Sanbase.Mock.prepare_mock2(&Sanbase.Balance.assets_held_by_address/1, {:ok, []})
    |> Sanbase.Mock.run_with_mocks(fn ->
      assert HistoricalBalance.assets_held_by_address(%{address: "0x123", infrastructure: "BTC"}) ==
               {:ok, []}
    end)
  end

  test "clickhouse returns error", _context do
    Sanbase.Mock.prepare_mock2(
      &Sanbase.Balance.assets_held_by_address/1,
      {:error, "Something went wrong"}
    )
    |> Sanbase.Mock.run_with_mocks(fn ->
      assert HistoricalBalance.assets_held_by_address(%{address: "0x123", infrastructure: "LTC"}) ==
               {:error, "Something went wrong"}
    end)
  end
end
