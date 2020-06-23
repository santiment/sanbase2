defmodule Sanbase.Clickhouse.HistoricalBalance.EthAssetsHeldByAdderssTest do
  use Sanbase.DataCase

  import Sanbase.Factory

  alias Sanbase.Clickhouse.HistoricalBalance.EthBalance

  setup do
    project = insert(:project, %{name: "Ethereum", slug: "ethereum", ticker: "ETH"})

    {:ok, [project: project]}
  end

  test "clickhouse returns list of results", context do
    rows = [[1000 * Sanbase.Math.ipow(10, 18)]]

    Sanbase.Mock.prepare_mock2(&Sanbase.ClickhouseRepo.query/2, {:ok, %{rows: rows}})
    |> Sanbase.Mock.run_with_mocks(fn ->
      assert EthBalance.assets_held_by_address("0x123") ==
               {:ok, [%{balance: 1000, slug: context.project.slug}]}
    end)
  end

  test "clickhouse returns no results", _context do
    Sanbase.Mock.prepare_mock2(&Sanbase.ClickhouseRepo.query/2, {:ok, %{rows: []}})
    |> Sanbase.Mock.run_with_mocks(fn ->
      assert EthBalance.assets_held_by_address("0x123") == {:ok, []}
    end)
  end

  test "clickhouse returns error", _context do
    Sanbase.Mock.prepare_mock2(&Sanbase.ClickhouseRepo.query/2, {:error, "error"})
    |> Sanbase.Mock.run_with_mocks(fn ->
      assert EthBalance.assets_held_by_address("0x123") == {:error, "error"}
    end)
  end
end
