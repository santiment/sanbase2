defmodule SanbaseWeb.Graphql.ApiDelayMiddlewareTest do
  use SanbaseWeb.ConnCase

  alias Sanbase.Influxdb.Measurement
  alias Sanbase.Github
  alias Sanbase.Auth.User
  alias Sanbase.Repo

  import SanbaseWeb.Graphql.TestHelpers

  setup do
    Github.Store.create_db()

    Github.Store.drop_measurement("SAN")
    Github.Store.drop_measurement("TEST1")
    Github.Store.drop_measurement("TEST2")

    hour_ago = hour_ago()

    Github.Store.import([
      %Measurement{
        timestamp: hour_ago |> DateTime.to_unix(:nanoseconds),
        fields: %{activity: 5},
        name: "SAN"
      }
    ])

    staked_user =
      %User{
        salt: User.generate_salt(),
        san_balance: Decimal.new(10),
        san_balance_updated_at: Timex.now()
      }
      |> Repo.insert!()

    not_staked_user =
      %User{
        salt: User.generate_salt()
      }
      |> Repo.insert!()

    {:ok, staked_user: staked_user, not_staked_user: not_staked_user}
  end

  test "Does not show real time data for anon users" do
    result =
      build_conn()
      |> post("/graphql", query_skeleton(githubActivityQuery(), "githubActivity"))

    activities = json_response(result, 200)["data"]["githubActivity"]

    refute %{"activity" => 5} in activities
  end

  test "Does not show real for user without SAN stake", context do
    conn = setup_jwt_auth(build_conn(), context.not_staked_user)

    result =
      conn
      |> post("/graphql", query_skeleton(githubActivityQuery(), "githubActivity"))

    activities = json_response(result, 200)["data"]["githubActivity"]

    refute %{"activity" => 5} in activities
  end

  test "Shows realtime data if user has SAN stake", context do
    conn = setup_jwt_auth(build_conn(), context.staked_user)

    result =
      conn
      |> post("/graphql", query_skeleton(githubActivityQuery(), "githubActivity"))

    activities = json_response(result, 200)["data"]["githubActivity"]

    assert %{"activity" => 5} in activities
  end

  defp githubActivityQuery() do
    """
    {
      githubActivity(
        ticker: "SAN",
        from: "#{week_ago()}",
        to: "#{now()}"
        interval: "1h") {
          activity
        }
    }
    """
  end

  defp now(), do: Timex.now()
  defp hour_ago(), do: Timex.shift(Timex.now(), hours: -1)
  defp week_ago(), do: Timex.shift(Timex.now(), days: -7)
end
