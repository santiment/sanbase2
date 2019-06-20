defmodule Sanbase.Clickhouse.HistoricalBalance.AssetsHeldByAdderssTest do
  use Sanbase.DataCase

  import Mock
  import Sanbase.Factory

  alias Sanbase.Clickhouse.HistoricalBalance

  require Sanbase.ClickhouseRepo

  setup do
    p1 = insert(:random_erc20_project)
    p2 = insert(:random_erc20_project)

    eth_project =
      insert(:project, %{name: "Ethereum", coinmarketcap_id: "ethereum", ticker: "ETH"})

    {:ok, [p1: p1, p2: p2, eth_project: eth_project]}
  end

  test "clickhouse returns list of results", context do
    with_mocks [
      {Sanbase.Clickhouse.HistoricalBalance.Erc20Balance, [:passthrough],
       assets_held_by_address: fn _ ->
         {:ok,
          [
            %{balance: 100.0, slug: context.p1.coinmarketcap_id},
            %{balance: 200.0, slug: context.p2.coinmarketcap_id}
          ]}
       end},
      {Sanbase.Clickhouse.HistoricalBalance.EthBalance, [:passthrough],
       assets_held_by_address: fn _ ->
         {:ok, [%{balance: 1000.0, slug: context.eth_project.coinmarketcap_id}]}
       end}
    ] do
      assert HistoricalBalance.assets_held_by_address("0x123") ==
               {:ok,
                [
                  %{slug: context.eth_project.coinmarketcap_id, balance: 1000.0},
                  %{slug: context.p1.coinmarketcap_id, balance: 100.0},
                  %{slug: context.p2.coinmarketcap_id, balance: 200.0}
                ]}
    end
  end

  test "clickhouse returns no results", _context do
    with_mocks [
      {Sanbase.Clickhouse.HistoricalBalance.Erc20Balance, [:passthrough],
       assets_held_by_address: fn _ ->
         {:ok, []}
       end},
      {Sanbase.Clickhouse.HistoricalBalance.EthBalance, [:passthrough],
       assets_held_by_address: fn _ ->
         {:ok, []}
       end}
    ] do
      assert HistoricalBalance.assets_held_by_address("0x123") ==
               {:ok, []}
    end
  end

  test "clickhouse returns error", _context do
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
      assert HistoricalBalance.assets_held_by_address("0x123") ==
               {:error, "Something went wrong"}
    end
  end
end
