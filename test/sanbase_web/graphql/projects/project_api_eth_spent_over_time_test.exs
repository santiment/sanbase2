defmodule SanbaseWeb.Graphql.ProjectApiEthSpentOverTimeTest do
  use SanbaseWeb.ConnCase, async: false

  alias Sanbase.Repo
  alias Sanbase.Model.{Project, ProjectEthAddress}
  alias Sanbase.DateTimeUtils

  import Mock
  import SanbaseWeb.Graphql.TestHelpers

  @eth_decimals 1_000_000_000_000_000_000

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
      datetime_from: DateTime.from_naive!(~N[2017-05-12 15:00:00], "Etc/UTC"),
      datetime_to: DateTime.from_naive!(~N[2017-05-18 20:00:00], "Etc/UTC")
    ]
  end

  test "project eth spent over time", context do
    dt1 = DateTimeUtils.from_iso8601!("2017-05-13T00:00:00Z") |> DateTime.to_unix()
    dt2 = DateTimeUtils.from_iso8601!("2017-05-14T00:00:00Z") |> DateTime.to_unix()
    dt3 = DateTimeUtils.from_iso8601!("2017-05-15T00:00:00Z") |> DateTime.to_unix()
    dt4 = DateTimeUtils.from_iso8601!("2017-05-16T00:00:00Z") |> DateTime.to_unix()
    dt5 = DateTimeUtils.from_iso8601!("2017-05-17T00:00:00Z") |> DateTime.to_unix()
    dt6 = DateTimeUtils.from_iso8601!("2017-05-18T00:00:00Z") |> DateTime.to_unix()

    with_mock Sanbase.ClickhouseRepo, [:passthrough],
      query: fn _, _ ->
        {:ok,
         %{
           rows: [
             [dt1, -500 * @eth_decimals],
             [dt2, -1500 * @eth_decimals],
             [dt3, -6000 * @eth_decimals],
             [dt4, 0],
             [dt5, 0],
             [dt6, -6500 * @eth_decimals]
           ]
         }}
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
               "ethSpent" => 500.0
             } in ethSpentOverTime

      assert %{
               "datetime" => "2017-05-14T00:00:00Z",
               "ethSpent" => 1500.0
             } in ethSpentOverTime

      assert %{
               "datetime" => "2017-05-15T00:00:00Z",
               "ethSpent" => 6000.0
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
               "ethSpent" => 6500.0
             } in ethSpentOverTime
    end
  end
end
