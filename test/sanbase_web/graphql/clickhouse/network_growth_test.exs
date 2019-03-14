defmodule SanbaseWeb.Graphql.Clickhouse.NetworkGrowthTest do
  use SanbaseWeb.ConnCase, async: false

  import SanbaseWeb.Graphql.TestHelpers
  import Mock
  import Sanbase.DateTimeUtils, only: [from_iso8601!: 1]
  import ExUnit.CaptureLog
  import Sanbase.Factory

  alias Sanbase.Clickhouse.NetworkGrowth

  setup do
    project = insert(:project, %{main_contract_address: "0x123"})

    [
      contract: project.main_contract_address,
      slug: project.coinmarketcap_id,
      from: from_iso8601!("2019-01-01T00:00:00Z"),
      to: from_iso8601!("2019-01-03T00:00:00Z"),
      interval: "1d"
    ]
  end

  test "returns data from Network growth calculation", context do
    with_mock NetworkGrowth,
      network_growth: fn _, _, _, _ ->
        {:ok,
         [
           %{new_addresses: 1, datetime: from_iso8601!("2019-01-01T00:00:00Z")},
           %{new_addresses: 2, datetime: from_iso8601!("2019-01-02T00:00:00Z")}
         ]}
      end do
      response = execute_query(context)
      result = parse_response(response)

      assert_called(
        NetworkGrowth.network_growth(context.contract, context.from, context.to, context.interval)
      )

      assert result == [
               %{"newAddresses" => 1, "datetime" => "2019-01-01T00:00:00Z"},
               %{"newAddresses" => 2, "datetime" => "2019-01-02T00:00:00Z"}
             ]
    end
  end

  test "returns empty array when there is no data", context do
    with_mock NetworkGrowth, network_growth: fn _, _, _, _ -> {:ok, []} end do
      response = execute_query(context)
      result = parse_response(response)

      assert_called(
        NetworkGrowth.network_growth(context.contract, context.from, context.to, context.interval)
      )

      assert result == []
    end
  end

  test "logs warning when calculation errors", context do
    with_mock NetworkGrowth,
      network_growth: fn _, _, _, _ -> {:error, "Some error description here"} end do
      assert capture_log(fn ->
               response = execute_query(context)
               result = parse_response(response)
               assert result == nil
             end) =~
               ~s/[warn] Can't calculate network growth for project with coinmarketcap_id: santiment. Reason: "Some error description here"/
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
