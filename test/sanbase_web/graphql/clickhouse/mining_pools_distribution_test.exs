defmodule SanbaseWeb.Graphql.Clickhouse.MiningPoolsDistributionTest do
  use SanbaseWeb.ConnCase, async: false

  import SanbaseWeb.Graphql.TestHelpers
  import Mock
  import Sanbase.DateTimeUtils, only: [from_iso8601!: 1]
  import ExUnit.CaptureLog
  import Sanbase.Factory

  @moduletag capture_log: true

  alias Sanbase.Clickhouse.MiningPoolsDistribution

  setup do
    %{user: user} = insert(:subscription_pro_sanbase, user: insert(:user))
    conn = setup_jwt_auth(build_conn(), user)

    [
      conn: conn,
      slug: "ethereum",
      from: from_iso8601!("2019-01-01T00:00:00Z"),
      to: from_iso8601!("2019-01-03T00:00:00Z"),
      interval: "1d"
    ]
  end

  test "works only for ethereum", context do
    error = "Currently only ethereum is supported!"

    with_mock MiningPoolsDistribution,
      distribution: fn _, _, _, _ -> {:error, error} end do
      assert capture_log(fn ->
               response = execute_query("unsupported", context)
               result = parse_response(response)
               assert result == nil
             end) =~
               graphql_error_msg("Mining Pools Distribution", "unsupported", error)
    end
  end

  test "returns data from calculation", context do
    with_mock MiningPoolsDistribution,
      distribution: fn _, _, _, _ ->
        {:ok,
         [
           %{
             top3: 0.1,
             top10: 0.4,
             other: 0.5,
             datetime: from_iso8601!("2019-01-01T00:00:00Z")
           },
           %{
             top3: 0.2,
             top10: 0.3,
             other: 0.5,
             datetime: from_iso8601!("2019-01-02T00:00:00Z")
           }
         ]}
      end do
      response = execute_query(context.slug, context)
      result = parse_response(response)

      assert_called(
        MiningPoolsDistribution.distribution(
          context.slug,
          context.from,
          context.to,
          context.interval
        )
      )

      assert result == [
               %{
                 "top3" => 0.1,
                 "top10" => 0.4,
                 "other" => 0.5,
                 "datetime" => "2019-01-01T00:00:00Z"
               },
               %{
                 "top3" => 0.2,
                 "top10" => 0.3,
                 "other" => 0.5,
                 "datetime" => "2019-01-02T00:00:00Z"
               }
             ]
    end
  end

  test "returns empty array when there is no data", context do
    with_mock MiningPoolsDistribution, distribution: fn _, _, _, _ -> {:ok, []} end do
      response = execute_query(context.slug, context)
      result = parse_response(response)

      assert_called(
        MiningPoolsDistribution.distribution(
          context.slug,
          context.from,
          context.to,
          context.interval
        )
      )

      assert result == []
    end
  end

  test "logs warning when calculation errors", context do
    error = "Some error description here"

    with_mock MiningPoolsDistribution,
      distribution: fn _, _, _, _ -> {:error, error} end do
      assert capture_log(fn ->
               response = execute_query(context.slug, context)
               result = parse_response(response)
               assert result == nil
             end) =~
               graphql_error_msg("Mining Pools Distribution", context.slug, error)
    end
  end

  test "returns error to the user when calculation errors", context do
    error = "Some error description here"

    with_mock MiningPoolsDistribution,
              [:passthrough],
              distribution: fn _, _, _, _ ->
                {:error, error}
              end do
      response = execute_query(context.slug, context)
      [first_error | _] = json_response(response, 200)["errors"]

      assert first_error["message"] =~
               graphql_error_msg("Mining Pools Distribution", context.slug, error)
    end
  end

  test "uses 1d as default interval", context do
    with_mock MiningPoolsDistribution, distribution: fn _, _, _, _ -> {:ok, []} end do
      query = """
        {
          miningPoolsDistribution(slug: "#{context.slug}", from: "#{context.from}", to: "#{
        context.to
      }"){
            datetime,
            top3,
            top10,
            other
          }
        }
      """

      context.conn
      |> post("/graphql", query_skeleton(query, "miningPoolsDistribution"))

      assert_called(
        MiningPoolsDistribution.distribution(context.slug, context.from, context.to, "1d")
      )
    end
  end

  defp parse_response(response) do
    json_response(response, 200)["data"]["miningPoolsDistribution"]
  end

  defp execute_query(slug, context) do
    query = mining_pools_distribution_query(slug, context.from, context.to, context.interval)

    context.conn
    |> post("/graphql", query_skeleton(query, "miningPoolsDistribution"))
  end

  defp mining_pools_distribution_query(slug, from, to, interval) do
    """
      {
        miningPoolsDistribution(slug: "#{slug}", from: "#{from}", to: "#{to}", interval: "#{
      interval
    }"){
          datetime,
          top3,
          top10,
          other
        }
      }
    """
  end
end
