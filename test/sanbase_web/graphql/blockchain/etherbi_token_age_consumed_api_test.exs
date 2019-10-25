defmodule Sanbase.Etherbi.TokenAgeConsumedApiTest do
  use SanbaseWeb.ConnCase, async: false

  import Mock
  import Sanbase.Factory
  import Sanbase.TestHelpers
  import SanbaseWeb.Graphql.TestHelpers

  setup do
    %{user: user} = insert(:subscription_pro_sanbase, user: insert(:user))

    conn = setup_jwt_auth(build_conn(), user)

    project = insert(:project)
    datetimes = generate_datetimes(~U[2017-05-13 00:00:00Z], "1d", 3)

    [
      slug: project.slug,
      from: List.first(datetimes),
      to: List.last(datetimes),
      datetimes: datetimes,
      conn: conn
    ]
  end

  test "when no interval is provided", context do
    %{datetimes: datetimes} = context

    with_mocks([
      {Sanbase.Metric, [:passthrough],
       [
         first_datetime: fn _, _ -> {:ok, context.from} end,
         get: fn _, _, _, _, _, _ ->
           {:ok,
            [
              %{datetime: Enum.at(datetimes, 0), value: 100},
              %{datetime: Enum.at(datetimes, 1), value: 200},
              %{datetime: Enum.at(datetimes, 2), value: 300}
            ]}
         end
       ]}
    ]) do
      query = """
      {
        tokenAgeConsumed(
          slug: "#{context.slug}",
          from: "#{context.from}",
          to: "#{context.to}",
          interval: "") {
            datetime
            tokenAgeConsumed
        }
      }
      """

      result =
        context.conn
        |> post("/graphql", query_skeleton(query, "tokenAgeConsumed"))
        |> json_response(200)

      token_age_consumed = result["data"]["tokenAgeConsumed"]

      assert token_age_consumed == [
               %{"datetime" => "2017-05-13T00:00:00Z", "tokenAgeConsumed" => 100},
               %{"datetime" => "2017-05-14T00:00:00Z", "tokenAgeConsumed" => 200},
               %{"datetime" => "2017-05-15T00:00:00Z", "tokenAgeConsumed" => 300}
             ]
    end
  end

  test "when interval is provided", context do
    %{datetimes: datetimes} = context

    with_mocks([
      {Sanbase.Metric, [:passthrough],
       [
         get: fn _, _, _, _, _, _ ->
           {:ok,
            [
              %{datetime: Enum.at(datetimes, 0), value: 100},
              %{datetime: Enum.at(datetimes, 1), value: 200},
              %{datetime: Enum.at(datetimes, 2), value: 300}
            ]}
         end
       ]}
    ]) do
      query = """
      {
        tokenAgeConsumed(
          slug: "#{context.slug}",
          from: "#{context.from}",
          to: "#{context.to}",
          interval: "1d") {
            datetime
            tokenAgeConsumed
        }
      }
      """

      result =
        context.conn
        |> post("/graphql", query_skeleton(query, "tokenAgeConsumed"))
        |> json_response(200)

      token_age_consumed = result["data"]["tokenAgeConsumed"]

      assert token_age_consumed == [
               %{"datetime" => "2017-05-13T00:00:00Z", "tokenAgeConsumed" => 100},
               %{"datetime" => "2017-05-14T00:00:00Z", "tokenAgeConsumed" => 200},
               %{"datetime" => "2017-05-15T00:00:00Z", "tokenAgeConsumed" => 300}
             ]
    end
  end
end
