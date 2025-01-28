defmodule SanbaseWeb.Graphql.ProjectApiEthSpentOverTimeTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.TestHelpers
  import SanbaseWeb.Graphql.TestHelpers
  import Sanbase.Factory

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
    [dt0, dt1, dt2, dt3, dt4, dt5, dt6] =
      generate_datetimes(~U[2017-05-12T00:00:00Z], "1d", 7) |> Enum.map(&DateTime.to_unix/1)

    # Historical Balances Changes uses internally the historical balances query,
    # so that's what needs to be mocked
    rows = [
      [dt0, 20000, 1],
      [dt1, 19500, 1],
      [dt2, 18000, 1],
      [dt3, 12000, 1],
      [dt4, 0, 0],
      [dt5, 0, 0],
      [dt6, 5500, 1]
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
