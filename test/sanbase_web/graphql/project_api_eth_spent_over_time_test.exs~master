defmodule SanbaseWeb.Graphql.ProjectApiEthSpentOverTimeTest do
  use SanbaseWeb.ConnCase, async: false

  alias Sanbase.Model.{
    Project,
    ProjectEthAddress
  }

  alias Sanbase.Repo

  import SanbaseWeb.Graphql.TestHelpers
  import Mock

  setup do
    ticker = "TESTXYZ"

    p =
      %Project{}
      |> Project.changeset(%{name: "Santiment", ticker: ticker, coinmarketcap_id: "santiment"})
      |> Repo.insert!()

    project_address1 = "0x123a12345bc"

    %ProjectEthAddress{}
    |> ProjectEthAddress.changeset(%{
      project_id: p.id,
      address: project_address1
    })
    |> Repo.insert_or_update()

    project_address2 = "0x321321321"

    %ProjectEthAddress{}
    |> ProjectEthAddress.changeset(%{
      project_id: p.id,
      address: project_address2
    })
    |> Repo.insert!()

    [
      project: p,
      ticker: ticker,
      datetime_from: DateTime.from_naive!(~N[2017-05-13 15:00:00], "Etc/UTC"),
      datetime_to: DateTime.from_naive!(~N[2017-05-18 20:00:00], "Etc/UTC")
    ]
  end

  test "project eth spent over time", context do
    with_mock Sanbase.Clickhouse.EthTransfers,
      eth_spent_over_time: fn _, _, _, _ ->
        {:ok,
         [
           %{datetime: Timex.parse!("2017-05-13T00:00:00Z", "{ISO:Extended}"), eth_spent: 500},
           %{datetime: Timex.parse!("2017-05-14T00:00:00Z", "{ISO:Extended}"), eth_spent: 1500},
           %{datetime: Timex.parse!("2017-05-15T00:00:00Z", "{ISO:Extended}"), eth_spent: 6000},
           %{datetime: Timex.parse!("2017-05-16T00:00:00Z", "{ISO:Extended}"), eth_spent: 0},
           %{datetime: Timex.parse!("2017-05-17T00:00:00Z", "{ISO:Extended}"), eth_spent: 0},
           %{datetime: Timex.parse!("2017-05-18T00:00:00Z", "{ISO:Extended}"), eth_spent: 6500}
         ]}
      end do
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

      ethSpentOverTime = json_response(result, 200)["data"]["project"]["ethSpentOverTime"]

      assert length(ethSpentOverTime) == 6

      assert %{
               "datetime" => "2017-05-13T00:00:00Z",
               "ethSpent" => 500
             } in ethSpentOverTime

      assert %{
               "datetime" => "2017-05-14T00:00:00Z",
               "ethSpent" => 1500
             } in ethSpentOverTime

      assert %{
               "datetime" => "2017-05-15T00:00:00Z",
               "ethSpent" => 6000
             } in ethSpentOverTime

      assert %{
               "datetime" => "2017-05-16T00:00:00Z",
               "ethSpent" => 0
             } in ethSpentOverTime

      assert %{
               "datetime" => "2017-05-17T00:00:00Z",
               "ethSpent" => 0
             } in ethSpentOverTime

      assert %{
               "datetime" => "2017-05-18T00:00:00Z",
               "ethSpent" => 6500
             } in ethSpentOverTime
    end
  end
end
