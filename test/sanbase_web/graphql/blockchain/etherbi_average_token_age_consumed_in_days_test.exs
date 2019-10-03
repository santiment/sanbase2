defmodule Sanbase.Etherbi.AverageTokenAgeConsumedInDaysApiTest do
  use SanbaseWeb.ConnCase, async: false

  import Mock
  import Sanbase.Factory
  import Sanbase.TestHelpers
  import SanbaseWeb.Graphql.TestHelpers

  setup do
    %{user: user} = insert(:subscription_pro_sanbase, user: insert(:user))

    conn = setup_jwt_auth(build_conn(), user)

    project = insert(:random_erc20_project)

    datetimes = generate_datetimes(~U[2017-05-13 21:45:00Z], "1d", 4)

    [
      slug: project.slug,
      from: List.first(datetimes),
      to: List.last(datetimes),
      datetimes: datetimes,
      conn: conn
    ]
  end

  test "fetch token age consumed in days", context do
    %{datetimes: datetimes} = context

    with_mocks([
      {Sanbase.Clickhouse.Metric, [:passthrough],
       [
         get: fn
           "age_destroyed", _, _, _, _, _ ->
             {:ok,
              [
                %{datetime: Enum.at(datetimes, 0), value: 1000},
                %{datetime: Enum.at(datetimes, 1), value: 4000},
                %{datetime: Enum.at(datetimes, 2), value: 10000}
              ]}

           "transaction_volume", _, _, _, _, _ ->
             {:ok,
              [
                %{datetime: Enum.at(datetimes, 0), value: 100},
                %{datetime: Enum.at(datetimes, 1), value: 200},
                %{datetime: Enum.at(datetimes, 2), value: 250}
              ]}
         end
       ]}
    ]) do
      query = """
      {
        averageTokenAgeConsumedInDays(
          slug: "#{context.slug}",
          from: "#{context.from}",
          to: "#{context.to}",
          interval: "1d") {
            datetime
            tokenAge
        }
      }
      """

      result =
        context.conn
        |> post("/graphql", query_skeleton(query, "averageTokenAgeConsumedInDays"))
        |> json_response(200)

      token_age_consumed_in_days = result["data"]["averageTokenAgeConsumedInDays"]

      assert token_age_consumed_in_days == [
               %{"datetime" => "2017-05-13T21:45:00Z", "tokenAge" => 10.0},
               %{"datetime" => "2017-05-14T21:45:00Z", "tokenAge" => 20.0},
               %{"datetime" => "2017-05-15T21:45:00Z", "tokenAge" => 40.0}
             ]
    end
  end
end
