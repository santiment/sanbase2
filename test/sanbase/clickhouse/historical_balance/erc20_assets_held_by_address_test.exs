defmodule Sanbase.Clickhouse.HistoricalBalance.Erc20AssetsHeldByAdderssTest do
  use Sanbase.DataCase

  import Sanbase.Factory

  alias Sanbase.Clickhouse.HistoricalBalance.Erc20Balance

  require Sanbase.ClickhouseRepo

  setup do
    p1 = insert(:random_erc20_project)
    p2 = insert(:random_erc20_project)
    p3 = insert(:random_erc20_project)
    p4 = insert(:random_erc20_project)
    p5 = insert(:random_erc20_project)
    {:ok, [p1: p1, p2: p2, p3: p3, p4: p4, p5: p5]}
  end

  test "clickhouse returns list of results", context do
    rows = [
      [context.p1.main_contract_address, Sanbase.Math.ipow(10, context.p1.token_decimals) * 100],
      [context.p2.main_contract_address, Sanbase.Math.ipow(10, context.p2.token_decimals) * 255],
      [context.p3.main_contract_address, 0],
      [context.p4.main_contract_address, Sanbase.Math.ipow(10, context.p4.token_decimals) * 1643],
      [context.p5.main_contract_address, 0]
    ]

    Sanbase.Mock.prepare_mock2(&Sanbase.ClickhouseRepo.query/2, {:ok, %{rows: rows}})
    |> Sanbase.Mock.run_with_mocks(fn ->
      assert Erc20Balance.assets_held_by_address("0x123") ==
               {:ok,
                [
                  %{balance: 100, slug: context.p1.slug},
                  %{balance: 255, slug: context.p2.slug},
                  %{balance: 0.0, slug: context.p3.slug},
                  %{balance: 1643, slug: context.p4.slug},
                  %{balance: 0.0, slug: context.p5.slug}
                ]}
    end)
  end

  test "clickhouse returns no results", _context do
    Sanbase.Mock.prepare_mock2(&Sanbase.ClickhouseRepo.query/2, {:ok, %{rows: []}})
    |> Sanbase.Mock.run_with_mocks(fn ->
      assert Erc20Balance.assets_held_by_address("0x123") == {:ok, []}
    end)
  end

  test "clickhouse returns error", _context do
    Sanbase.Mock.prepare_mock2(&Sanbase.ClickhouseRepo.query/2, {:error, "error"})
    |> Sanbase.Mock.run_with_mocks(fn ->
      assert Erc20Balance.assets_held_by_address("0x123") == {:error, "error"}
    end)
  end
end
