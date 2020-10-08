defmodule Sanbase.Clickhouse.HistoricalBalance.Erc20AssetsHeldByAdderssTest do
  use Sanbase.DataCase

  import Sanbase.Factory

  alias Sanbase.Clickhouse.HistoricalBalance.Erc20Balance

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
      [context.p1.slug, 100.0],
      [context.p2.slug, 255.0],
      [context.p3.slug, 0.0],
      [context.p4.slug, 1643.0],
      [context.p5.slug, 0.0]
    ]

    Sanbase.Mock.prepare_mock2(&Sanbase.ClickhouseRepo.query/2, {:ok, %{rows: rows}})
    |> Sanbase.Mock.run_with_mocks(fn ->
      assert Erc20Balance.assets_held_by_address("0x123") ==
               {:ok,
                [
                  %{balance: 100.0, slug: context.p1.slug},
                  %{balance: 255.0, slug: context.p2.slug},
                  %{balance: 0.0, slug: context.p3.slug},
                  %{balance: 1643.0, slug: context.p4.slug},
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
      {:error, error} = Erc20Balance.assets_held_by_address("0x123")
      assert error =~ "Cannot execute database query."
    end)
  end
end
