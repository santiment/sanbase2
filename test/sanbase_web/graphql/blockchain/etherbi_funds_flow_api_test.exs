defmodule Sanbase.Etherbi.TransactionsApiTest do
  use SanbaseWeb.ConnCase, async: false

  import Mock
  import Sanbase.Factory
  import Sanbase.TestHelpers
  import SanbaseWeb.Graphql.TestHelpers

  setup do
    %{user: user} = insert(:subscription_pro_sanbase, user: insert(:user))
    conn = setup_jwt_auth(build_conn(), user)
    project = insert(:random_erc20_project)
    datetimes = generate_datetimes(~U[2017-05-13 00:00:00Z], "1d", 3)

    [
      datetimes: datetimes,
      slug: project.slug,
      from: List.first(datetimes),
      to: List.last(datetimes),
      conn: conn
    ]
  end

  test "fetch funds flow when no interval is provided", context do
    %{datetimes: datetimes} = context
    datetimes_unix = Enum.map(datetimes, &DateTime.to_unix/1)

    with_mock Sanbase.ClickhouseRepo,
      query: fn _, _ ->
        {:ok,
         %{
           rows: [
             [Enum.at(datetimes_unix, 0), 10],
             [Enum.at(datetimes_unix, 1), 1000],
             [Enum.at(datetimes_unix, 2), -2000]
           ]
         }}
      end do
      query = """
      {
        exchangeFundsFlow(
          slug: "#{context.slug}",
          from: "#{context.from}",
          to: "#{context.to}") {
            datetime
            inOutDifference
        }
      }
      """

      result =
        context.conn
        |> post("/graphql", query_skeleton(query, "exchangeFundsFlow"))
        |> json_response(200)

      funds_flow_list = result["data"]["exchangeFundsFlow"]

      assert funds_flow_list == [
               %{"datetime" => "2017-05-13T00:00:00Z", "inOutDifference" => 10},
               %{"datetime" => "2017-05-14T00:00:00Z", "inOutDifference" => 1000},
               %{"datetime" => "2017-05-15T00:00:00Z", "inOutDifference" => -2000}
             ]
    end
  end

  test "fetch funds flow", context do
    %{datetimes: datetimes} = context
    datetimes_unix = Enum.map(datetimes, &DateTime.to_unix/1)

    with_mock Sanbase.ClickhouseRepo,
      query: fn _, _ ->
        {:ok,
         %{
           rows: [
             [Enum.at(datetimes_unix, 0), 100],
             [Enum.at(datetimes_unix, 1), -1000],
             [Enum.at(datetimes_unix, 2), -2000]
           ]
         }}
      end do
      query = """
      {
        exchangeFundsFlow(
          slug: "#{context.slug}",
          from: "#{context.from}",
          to: "#{context.to}",
          interval: "1d") {
            datetime
            inOutDifference
        }
      }
      """

      result =
        context.conn
        |> post("/graphql", query_skeleton(query, "exchangeFundsFlow"))
        |> json_response(200)

      funds_flow_list = result["data"]["exchangeFundsFlow"]

      assert funds_flow_list == [
               %{"datetime" => "2017-05-13T00:00:00Z", "inOutDifference" => 100},
               %{"datetime" => "2017-05-14T00:00:00Z", "inOutDifference" => -1000},
               %{"datetime" => "2017-05-15T00:00:00Z", "inOutDifference" => -2000}
             ]
    end
  end
end
