defmodule Sanbase.Clickhouse.TokenVelocityApiTest do
  use SanbaseWeb.ConnCase, async: false

  import Mock
  import Sanbase.Factory
  import Sanbase.TestHelpers
  import SanbaseWeb.Graphql.TestHelpers
  import ExUnit.CaptureLog

  setup do
    %{user: user} = insert(:subscription_pro_sanbase, user: insert(:user))
    conn = setup_jwt_auth(build_conn(), user)

    project = insert(:random_erc20_project)
    datetimes = generate_datetimes(~U[2017-05-13 00:00:00Z], "1d", 8)

    [
      slug: project.slug,
      from: List.first(datetimes),
      to: List.last(datetimes),
      datetimes: datetimes,
      conn: conn
    ]
  end

  test "fetch token velocity", context do
    %{datetimes: datetimes} = context

    with_mock Sanbase.ClickhouseRepo, [:passthrough],
      query: fn _, _ ->
        {:ok,
         %{
           rows: [
             [Enum.at(datetimes, 0) |> DateTime.to_unix(), 3],
             [Enum.at(datetimes, 1) |> DateTime.to_unix(), 2],
             [Enum.at(datetimes, 2) |> DateTime.to_unix(), 1],
             [Enum.at(datetimes, 3) |> DateTime.to_unix(), 2.4],
             [Enum.at(datetimes, 4) |> DateTime.to_unix(), 4],
             [Enum.at(datetimes, 5) |> DateTime.to_unix(), 0.96],
             [Enum.at(datetimes, 6) |> DateTime.to_unix(), 0.5],
             [Enum.at(datetimes, 7) |> DateTime.to_unix(), 3]
           ]
         }}
      end do
      query = """
      {
        tokenVelocity(
          slug: "#{context.slug}",
          from: "#{context.from}",
          to: "#{context.to}",
          interval: "1d") {
            datetime
            tokenVelocity
        }
      }
      """

      result =
        context.conn
        |> post("/graphql", query_skeleton(query, "tokenVelocity"))
        |> json_response(200)

      token_velocity = result["data"]["tokenVelocity"]

      assert token_velocity == [
               %{"datetime" => "2017-05-13T00:00:00Z", "tokenVelocity" => 3},
               %{"datetime" => "2017-05-14T00:00:00Z", "tokenVelocity" => 2},
               %{"datetime" => "2017-05-15T00:00:00Z", "tokenVelocity" => 1},
               %{"datetime" => "2017-05-16T00:00:00Z", "tokenVelocity" => 2.4},
               %{"datetime" => "2017-05-17T00:00:00Z", "tokenVelocity" => 4},
               %{"datetime" => "2017-05-18T00:00:00Z", "tokenVelocity" => 0.96},
               %{"datetime" => "2017-05-19T00:00:00Z", "tokenVelocity" => 0.5},
               %{"datetime" => "2017-05-20T00:00:00Z", "tokenVelocity" => 3}
             ]
    end
  end
end
