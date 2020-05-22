defmodule SanbaseWeb.Graphql.ProjectApiEthSpentOverTimeTest do
  use SanbaseWeb.ConnCase, async: false

  import Mock
  import Sanbase.TestHelpers
  import SanbaseWeb.Graphql.TestHelpers
  import Sanbase.Factory

  alias Sanbase.DateTimeUtils

  @eth_decimals 1_000_000_000_000_000_000

  setup do
    ticker = "TESTXYZ"

    p = insert(:project, %{name: "Santiment", ticker: ticker, slug: "santiment"})
    insert(:project_eth_address, %{project_id: p.id})
    insert(:project_eth_address, %{project_id: p.id})

    [
      project: p,
      ticker: ticker,
      datetime_from: DateTime.from_naive!(~N[2017-05-12 15:00:00], "Etc/UTC"),
      datetime_to: DateTime.from_naive!(~N[2017-05-18 20:00:00], "Etc/UTC")
    ]
  end

  test "project eth spent over time", context do
    [dt1, dt2, dt3, dt4, dt5, dt6] =
      generate_datetimes(~U[2017-05-13T00:00:00Z], "1d", 6) |> Enum.map(&DateTime.to_unix/1)

    rows = [
      [dt1, -500 * @eth_decimals],
      [dt2, -1500 * @eth_decimals],
      [dt3, -6000 * @eth_decimals],
      [dt4, 0],
      [dt5, 0],
      [dt6, -6500 * @eth_decimals]
    ]

    Sanbase.Mock.prepare_mock2(&Sanbase.ClickhouseRepo.query/2, {:ok, %{rows: rows}})
    |> Sanbase.Mock.run_with_mocks(fn ->
      query = """
      {
        project(id: #{context.project.id}) {
          ethSpentOverTime(
            from: "#{context.datetime_from}",
            to: "#{context.datetime_to}",
            interval: "1d"){
              datetime,
              ethSpent
          }
        }
      }
      """

      result =
        context.conn
        |> post("/graphql", query_skeleton(query, "project"))

      eth_spent_over_time = json_response(result, 200)["data"]["project"]["ethSpentOverTime"]

      assert length(eth_spent_over_time) == 6

      assert %{"datetime" => "2017-05-13T00:00:00Z", "ethSpent" => 500.0} in eth_spent_over_time
      assert %{"datetime" => "2017-05-14T00:00:00Z", "ethSpent" => 1500.0} in eth_spent_over_time
      assert %{"datetime" => "2017-05-15T00:00:00Z", "ethSpent" => 6000.0} in eth_spent_over_time
      assert %{"datetime" => "2017-05-16T00:00:00Z", "ethSpent" => 0.0} in eth_spent_over_time
      assert %{"datetime" => "2017-05-17T00:00:00Z", "ethSpent" => 0.0} in eth_spent_over_time
      assert %{"datetime" => "2017-05-18T00:00:00Z", "ethSpent" => 6500.0} in eth_spent_over_time
    end)
  end
end
