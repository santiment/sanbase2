defmodule SanbaseWeb.Graphql.Clickhouse.TopHoldersTest do
  use SanbaseWeb.ConnCase, async: false

  import SanbaseWeb.Graphql.TestHelpers
  import Mock
  import Sanbase.DateTimeUtils, only: [from_iso8601!: 1]
  import ExUnit.CaptureLog
  import Sanbase.Factory

  alias Sanbase.Clickhouse.TopHolders

  setup do
    user = insert(:staked_user)
    conn = setup_jwt_auth(build_conn(), user)

    project = insert(:project, %{coinmarketcap_id: "ethereum", ticker: "ETH"})

    [
      conn: conn,
      slug: project.coinmarketcap_id,
      contract: "ETH",
      token_decimals: 18,
      from: from_iso8601!("2019-01-01T00:00:00Z"),
      to: from_iso8601!("2019-01-03T00:00:00Z"),
      number_of_holders: 10
    ]
  end

  test "returns data from TopHolders calculation", context do
    with_mock TopHolders,
      percent_of_total_supply: fn _, _, _, _, _ ->
        {:ok,
         [
           %{
             in_exchanges: 7.6,
             outside_exchanges: 5.2,
             in_top_holders_total: 12.8,
             datetime: from_iso8601!("2019-01-01T00:00:00Z")
           },
           %{
             in_exchanges: 7.1,
             outside_exchanges: 5.1,
             in_top_holders_total: 12.2,
             datetime: from_iso8601!("2019-01-02T00:00:00Z")
           }
         ]}
      end do
      response = execute_query(context)
      holders = parse_response(response)

      assert_called(
        TopHolders.percent_of_total_supply(
          context.contract,
          context.token_decimals,
          context.number_of_holders,
          context.from,
          context.to
        )
      )

      assert holders == [
               %{
                 "in_exchanges" => 7.6,
                 "outside_exchanges" => 5.2,
                 "in_top_holders_total" => 12.8,
                 "datetime" => "2019-01-01T00:00:00Z"
               },
               %{
                 "in_exchanges" => 7.1,
                 "outside_exchanges" => 5.1,
                 "in_top_holders_total" => 12.2,
                 "datetime" => "2019-01-02T00:00:00Z"
               }
             ]
    end
  end

  test "returns empty array when there is no data", context do
    with_mock TopHolders, percent_of_total_supply: fn _, _, _, _, _ -> {:ok, []} end do
      response = execute_query(context)
      holders = parse_response(response)

      assert_called(
        TopHolders.percent_of_total_supply(
          context.contract,
          context.token_decimals,
          context.number_of_holders,
          context.from,
          context.to
        )
      )

      assert holders == []
    end
  end

  test "logs warning when calculation errors", context do
    with_mock TopHolders,
      percent_of_total_supply: fn _, _, _, _, _ -> {:error, "error"} end do
      assert capture_log(fn ->
               response = execute_query(context)
               holders = parse_response(response)
               assert holders == nil
             end) =~
               ~s/[warn] Can't calculate top holders - percent of total supply for slug: #{
                 context.slug
               }. Reason: "error"/
    end
  end

  defp parse_response(response) do
    json_response(response, 200)["data"]["topHoldersPercentOfTotalSupply"]
  end

  defp execute_query(context) do
    query =
      top_holders_percent_supply_query(
        context.slug,
        context.number_of_holders,
        context.from,
        context.to
      )

    context.conn
    |> post("/graphql", query_skeleton(query, "topHoldersPercentOfTotalSupply"))
  end

  defp top_holders_percent_supply_query(slug, number_of_holders, from, to) do
    """
      {
        topHoldersPercentOfTotalSupply(
          slug: "#{slug}",
          number_of_holders: #{number_of_holders}
          from: "#{from}",
          to: "#{to}"
        ){
          datetime,
          in_exchanges,
          outside_exchanges,
          in_top_holders_total
        }
      }
    """
  end
end
