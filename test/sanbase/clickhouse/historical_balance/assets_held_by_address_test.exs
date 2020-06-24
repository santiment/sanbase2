defmodule Sanbase.Clickhouse.HistoricalBalance.AssetsHeldByAdderssTest do
  use Sanbase.DataCase

  import Mock
  import Sanbase.Factory

  alias Sanbase.Clickhouse.HistoricalBalance

  setup do
    p1 = insert(:random_erc20_project)
    p2 = insert(:random_erc20_project)

    eth_project = insert(:project, %{name: "Ethereum", slug: "ethereum", ticker: "ETH"})

    {:ok, [p1: p1, p2: p2, eth_project: eth_project]}
  end

  test "clickhouse returns list of results", context do
    with_mocks [
      {Sanbase.Clickhouse.HistoricalBalance.Erc20Balance, [:passthrough],
       assets_held_by_address: fn _ ->
         {:ok,
          [
            %{balance: 100.0, slug: context.p1.slug},
            %{balance: 200.0, slug: context.p2.slug}
          ]}
       end},
      {Sanbase.Clickhouse.HistoricalBalance.EthBalance, [:passthrough],
       assets_held_by_address: fn _ ->
         {:ok, [%{balance: 1000.0, slug: context.eth_project.slug}]}
       end}
    ] do
      assert HistoricalBalance.assets_held_by_address(%{address: "0x123", infrastructure: "ETH"}) ==
               {:ok,
                [
                  %{slug: context.eth_project.slug, balance: 1000.0},
                  %{slug: context.p1.slug, balance: 100.0},
                  %{slug: context.p2.slug, balance: 200.0}
                ]}
    end
  end

  test "clickhouse returns no results", _context do
    with_mocks [
      {Sanbase.Clickhouse.HistoricalBalance.BtcBalance, [:passthrough],
       assets_held_by_address: fn _ ->
         {:ok, []}
       end}
    ] do
      assert HistoricalBalance.assets_held_by_address(%{address: "0x123", infrastructure: "BTC"}) ==
               {:ok, []}
    end
  end

  test "clickhouse returns error", _context do
    with_mocks [
      {Sanbase.Clickhouse.HistoricalBalance.LtcBalance, [:passthrough],
       assets_held_by_address: fn _ ->
         {:error, "Something went wrong"}
       end}
    ] do
      assert HistoricalBalance.assets_held_by_address(%{address: "0x123", infrastructure: "LTC"}) ==
               {:error, "Something went wrong"}
    end
  end
end
