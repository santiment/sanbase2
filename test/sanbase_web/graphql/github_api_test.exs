defmodule Sanbase.Github.GithubApiTest do
  use SanbaseWeb.ConnCase
  use Phoenix.ConnTest

  alias Sanbase.Influxdb.Measurement
  alias Sanbase.Github

  setup do
    Github.Store.create_db()

    Github.Store.drop_measurement("SAN")
    Github.Store.drop_measurement("TEST1")
    Github.Store.drop_measurement("TEST2")

    Github.Store.import([
      %Measurement{
        timestamp: days_ago_start_of_day(5) |> DateTime.to_unix(:nanoseconds),
        fields: %{activity: 5},
        name: "SAN"
      },
      %Measurement{
        timestamp: days_ago_start_of_day(4) |> DateTime.to_unix(:nanoseconds),
        fields: %{activity: 10},
        name: "SAN"
      },
      %Measurement{
        timestamp: days_ago_start_of_day(3) |> DateTime.to_unix(:nanoseconds),
        fields: %{activity: 15},
        name: "SAN"
      },
      %Measurement{
        timestamp: days_ago_start_of_day(5) |> DateTime.to_unix(:nanoseconds),
        fields: %{activity: 5},
        name: "TEST1"
      },
      %Measurement{
        timestamp: days_ago_start_of_day(4) |> DateTime.to_unix(:nanoseconds),
        fields: %{activity: 10},
        name: "TEST2"
      }
    ])

  end

  test "fetching github time series data", context do
    query = """
    {
      githubActivity(
        repository: "SAN",
        from: "#{days_ago_start_of_day(5)}",
        interval: "1d") {
          activity
        }
    }
    """

    result =
      context.conn
      |> post("/graphql", query_skeleton(query, "githubActivity"))

    activities = json_response(result, 200)["data"]["githubActivity"]

    assert %{"activity" => 5} in activities
    assert %{"activity" => 10} in activities
    assert %{"activity" => 15} in activities
  end

  test "fetch github time series data for larger interval sums all activities", context do
    query = """
    {
      githubActivity(
        repository: "SAN",
        from: "#{days_ago_start_of_day(6)}",
        interval: "6d") {
          activity
        }
    }
    """

    result =
      context.conn
      |> post("/graphql", query_skeleton(query, "githubActivity"))

    activities = json_response(result, 200)["data"]["githubActivity"]

    assert Enum.count(activities) == 1
    assert %{"activity" => 30} in activities
  end

  test "retrive all repository names", context do
    query = """
    {
      githubAvailablesRepos
    }
    """

    result =
    context.conn
    |> post("/graphql", query_skeleton(query, "githubAvailablesRepos"))

    repos = json_response(result, 200)["data"]["githubAvailablesRepos"]

    assert ["SAN", "TEST1", "TEST2"] == Enum.sort(repos)
  end

  defp days_ago_start_of_day(days) do
    Timex.today()
    |> Timex.shift(days: -days)
    |> Timex.end_of_day()
    |> Timex.to_datetime()
  end

  defp query_skeleton(query, query_name) do
    %{
      "operationName" => "#{query_name}",
      "query" => "query #{query_name} #{query}",
      "variables" => "{}"
    }
  end
end