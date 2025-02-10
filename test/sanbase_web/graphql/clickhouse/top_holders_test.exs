defmodule SanbaseWeb.Graphql.Clickhouse.TopHoldersTest do
  use SanbaseWeb.ConnCase, async: false

  import ExUnit.CaptureLog
  import Mock
  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  alias Sanbase.Clickhouse.TopHolders

  @moduletag capture_log: true

  setup do
    %{user: user} = insert(:subscription_pro_sanbase, user: insert(:user))
    conn = setup_jwt_auth(build_conn(), user)

    project = insert(:project, %{slug: "ethereum", ticker: "ETH"})

    [
      conn: conn,
      slug: project.slug,
      contract: "ETH",
      token_decimals: 18,
      interval: "1d",
      from: ~U[2019-01-01 00:00:00Z],
      to: ~U[2019-01-03 00:00:00Z],
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
             datetime: ~U[2019-01-01 00:00:00Z]
           },
           %{
             in_exchanges: 7.1,
             outside_exchanges: 5.1,
             in_top_holders_total: 12.2,
             datetime: ~U[2019-01-02 00:00:00Z]
           }
         ]}
      end do
      response = execute_query(context)
      holders = parse_response(response)

      assert_called(
        TopHolders.percent_of_total_supply(
          context.slug,
          context.number_of_holders,
          context.from,
          context.to,
          context.interval
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
          context.slug,
          context.number_of_holders,
          context.from,
          context.to,
          context.interval
        )
      )

      assert holders == []
    end
  end

  test "logs warning when calculation errors", context do
    error = "Some error description here"

    with_mock TopHolders,
      percent_of_total_supply: fn _, _, _, _, _ -> {:error, error} end do
      assert capture_log(fn ->
               response = execute_query(context)
               holders = parse_response(response)
               assert holders == nil
             end) =~
               graphql_error_msg("Top Holders - percent of total supply", context.slug, error)
    end
  end

  test "returns error to the user when calculation errors", context do
    error = "Some error description here"

    with_mock TopHolders,
              [:passthrough],
              percent_of_total_supply: fn _, _, _, _, _ ->
                {:error, error}
              end do
      response = execute_query(context)
      [first_error | _] = json_response(response, 200)["errors"]

      assert first_error["message"] =~
               graphql_error_msg("Top Holders - percent of total supply", context.slug, error)
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
        context.to,
        context.interval
      )

    post(context.conn, "/graphql", query_skeleton(query, "topHoldersPercentOfTotalSupply"))
  end

  defp top_holders_percent_supply_query(slug, number_of_holders, from, to, interval) do
    """
      {
        topHoldersPercentOfTotalSupply(
          slug: "#{slug}"
          number_of_holders: #{number_of_holders}
          from: "#{from}"
          to: "#{to}"
          interval: "#{interval}"
        ){
          datetime
          in_exchanges
          outside_exchanges
          in_top_holders_total
        }
      }
    """
  end
end
