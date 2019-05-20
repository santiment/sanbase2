defmodule SanbaseWeb.Graphql.Clickhouse.NtworkGrowthTest do
  use SanbaseWeb.ConnCase
  require Sanbase.ClickhouseRepo
  import SanbaseWeb.Graphql.TestHelpers
  import Sanbase.DateTimeUtils, only: [from_iso8601!: 1]
  import Mock
  import ExUnit.CaptureLog
  import Sanbase.Factory

  alias Sanbase.Clickhouse.NetworkGrowth

  setup do
    project = insert(:project, %{main_contract_address: "0x123"})

    [
      project: project,
      slug: project.coinmarketcap_id,
      contract: project.main_contract_address,
      from: from_iso8601!("2019-01-01T00:00:00Z"),
      to: from_iso8601!("2019-01-03T00:00:00Z"),
      interval: "1d"
    ]
  end

  test "returns data from MVRV calculation", context do
    with_mock NetworkGrowth,
      network_growth: fn _, _, _, _ ->
        {:ok,
         [
           %{new_addresses: 1000, datetime: from_iso8601!("2019-01-01T00:00:00Z")},
           %{new_addresses: 2000, datetime: from_iso8601!("2019-01-02T00:00:00Z")}
         ]}
      end do
      response = execute_query(context)
      ratios = parse_response(response)

      assert ratios == [
               %{"newAddresses" => 1000, "datetime" => "2019-01-01T00:00:00Z"},
               %{"newAddresses" => 2000, "datetime" => "2019-01-02T00:00:00Z"}
             ]
    end
  end

  test "returns empty array when there is no data", context do
    with_mock NetworkGrowth, network_growth: fn _, _, _, _ -> {:ok, []} end do
      response = execute_query(context)
      ratios = parse_response(response)

      assert ratios == []
    end
  end

  test "logs warning when calculation errors", context do
    error = "Some error description here"

    with_mock NetworkGrowth,
      network_growth: fn _, _, _, _ -> {:error, error} end do
      assert capture_log(fn ->
               response = execute_query(context)
               result = parse_response(response)
               assert result == nil
             end) =~
               graphql_error_msg("Network Growth", context.slug, error)
    end
  end

  test "uses 1d as default interval", context do
    with_mock NetworkGrowth, network_growth: fn _, _, _, _ -> {:ok, []} end do
      query = """
        {
          networkGrowth(slug: "#{context.slug}", from: "#{context.from}", to: "#{context.to}"){
            datetime,
            newAddresses
          }
        }
      """

      context.conn
      |> post("/graphql", query_skeleton(query, "networkGrowth"))

      assert_called(
        NetworkGrowth.network_growth(context.contract, context.from, context.to, "1d")
      )
    end
  end

  defp parse_response(response) do
    json_response(response, 200)["data"]["networkGrowth"]
  end

  defp execute_query(context) do
    query = network_growth_query(context.slug, context.from, context.to, context.interval)

    context.conn
    |> post("/graphql", query_skeleton(query, "networkGrowth"))
  end

  defp network_growth_query(slug, from, to, interval) do
    """
      {
        networkGrowth(slug: "#{slug}", from: "#{from}", to: "#{to}", interval: "#{interval}"){
          datetime,
          newAddresses
        }
      }
    """
  end
end
