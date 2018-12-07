defmodule SanbaseWeb.Graphql.Clickhouse.NtworkGrowthTest do
  use SanbaseWeb.ConnCase
  require Sanbase.ClickhouseRepo
  import SanbaseWeb.Graphql.TestHelpers
  import Sanbase.DateTimeUtils, only: [from_iso8601_to_unix!: 1]
  import Mock
  import Sanbase.Factory

  setup do
    project = insert(:project, %{main_contract_address: "0x123"})

    [
      project: project
    ]
  end

  test "network growth works", context do
    with_mock Sanbase.ClickhouseRepo,
      query: fn _, _ ->
        {:ok,
         %{
           rows: [
             [from_iso8601_to_unix!("2018-12-01T00:00:00Z"), 5],
             [from_iso8601_to_unix!("2018-12-02T00:00:00Z"), 8]
           ]
         }}
      end do
      query = """
      {
        networkGrowth(
          slug: "#{context.project.coinmarketcap_id}",
          from: "2018-12-01T00:00:00Z",
          to: "2018-12-07T00:00:00Z",
          interval: "1d"
        )
        {
          datetime,
          newAddresses
        }
      }
      """

      result =
        context.conn
        |> post("/graphql", query_skeleton(query, "networkGrowth"))

      network_growth = json_response(result, 200)["data"]["networkGrowth"]

      assert network_growth == [
               %{"datetime" => "2018-12-01T00:00:00Z", "newAddresses" => 5},
               %{"datetime" => "2018-12-02T00:00:00Z", "newAddresses" => 8}
             ]
    end
  end
end
