defmodule SanbaseWeb.Graphql.Clickhouse.AssetsHeldByAdderssApiTest do
  use SanbaseWeb.ConnCase, async: false

  import Mock
  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers
  import ExUnit.CaptureLog

  require Sanbase.ClickhouseRepo

  @eth_decimals 1_000_000_000_000_000_000

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
                 [@eth_decimals * 1000]
               ]
             }}
        end
      end do
      address = "0x123"

      query = asses_held_by_address_query(address)

      result =
        context.conn
        |> post("/graphql", query_skeleton(query, "assetsHeldByAddress"))
        |> json_response(200)

      assert result == %{
               "data" => %{
                 "assetsHeldByAddress" => [
                   %{"balance" => 1.0e3, "slug" => context.eth_project.coinmarketcap_id},
                   %{"balance" => 100.0, "slug" => context.p1.coinmarketcap_id},
                   %{"balance" => 200.0, "slug" => context.p2.coinmarketcap_id}
                 ]
               }
             }
    end
  end

  test "clickhouse returns empty list", context do
    with_mock Sanbase.ClickhouseRepo,
      query: fn _, _ ->
        {:ok, %{rows: []}}
      end do
      address = "0x123"

      query = asses_held_by_address_query(address)

      result =
        context.conn
        |> post("/graphql", query_skeleton(query, "assetsHeldByAddress"))
        |> json_response(200)

      assert result == %{"data" => %{"assetsHeldByAddress" => []}}
    end
  end

  test "clickhouse returns error", context do
    with_mock Sanbase.ClickhouseRepo,
      query: fn _, _ ->
        {:error, "Something went wrong"}
      end do
      address = "0x123"

      query = asses_held_by_address_query(address)

      assert capture_log(fn ->
               result =
                 context.conn
                 |> post("/graphql", query_skeleton(query, "assetsHeldByAddress"))
                 |> json_response(200)

               error = result["errors"] |> List.first()

               assert error["message"] =~
                        "Can't fetch Assets held by address for address: #{address}"
             end) =~ "Can't fetch Assets held by address for address: #{address}"
    end
  end

  defp asses_held_by_address_query(address) do
    """
      {
        assetsHeldByAddress(
          address: "#{address}"
        ){
            slug
            balance
        }
      }
    """
  end
end
