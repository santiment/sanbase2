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
    with_mock Sanbase.ClickhouseRepo,
      query: fn query, _ ->
        # If the query contains `contract` return erc20 data, ethereum data otherwise
        case String.contains?(query, "contract") do
          true ->
            {:ok,
             %{
               rows: [
                 [
                   context.p1.main_contract_address,
                   Sanbase.Math.ipow(10, context.p1.token_decimals) * 100
                 ],
                 [
                   context.p2.main_contract_address,
                   Sanbase.Math.ipow(10, context.p1.token_decimals) * 200
                 ]
               ]
             }}

          false ->
            {:ok,
             %{
               rows: [
                 [Sanbase.Math.ipow(10, 18) * 1000]
               ]
             }}
        end
      end do
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
    with_mock Sanbase.ClickhouseRepo,
      query: fn _, _ ->
        {:ok,
         %{
           rows: []
         }}
      end do
      assert HistoricalBalance.assets_held_by_address("0x123") ==
               {:ok, []}
    end
  end

  test "clickhouse returns error", _context do
    with_mock Sanbase.ClickhouseRepo,
      query: fn _, _ ->
        {:error, "Cannot execute query due to error"}
      end do
      assert HistoricalBalance.assets_held_by_address("0x123") ==
               {:error,
                "Cannot execute ClickHouse query. Reason: no case clause matching: {:error, \"Cannot execute query due to error\"}\n"}
    end
  end
end
