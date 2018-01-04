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

    datetime1 = DateTime.from_naive!(~N[2017-05-13 21:45:00], "Etc/UTC")
    datetime2 = DateTime.from_naive!(~N[2017-05-14 21:45:00], "Etc/UTC")
    datetime3 = DateTime.from_naive!(~N[2017-05-15 21:45:00], "Etc/UTC")

    Github.Store.import([
      %Measurement{
        timestamp: datetime2 |> DateTime.to_unix(:nanoseconds),
        fields: %{activity: 5},
        name: "SAN"
      },
      %Measurement{
        timestamp: datetime3 |> DateTime.to_unix(:nanoseconds),
        fields: %{activity: 10},
        name: "SAN"
      },

      %Measurement{
        timestamp: datetime2 |> DateTime.to_unix(:nanoseconds),
        fields: %{activity: 5},
        name: "TEST1"
      },
      %Measurement{
        timestamp: datetime3 |> DateTime.to_unix(:nanoseconds),
        fields: %{activity: 10},
        name: "TEST2"
      }
    ])

    [datetime1: datetime1, datetime2: datetime2, datetime3: datetime3]
  end

  test "fetching github time series data", context do
    query = """
    {
      githubActivity(
        repository: "SAN",
        from: "#{context.datetime1}",
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
  end

  test "fetch github time series data for larger interval sums all activities", context do
    query = """
    {
      githubActivity(
        repository: "SAN",
        from: "#{context.datetime1}",
        to: "#{context.datetime3}",
        interval: "2d") {
          activity
        }
    }
    """

    result =
      context.conn
      |> post("/graphql", query_skeleton(query, "githubActivity"))

    activities = json_response(result, 200)["data"]["githubActivity"]

    assert Enum.count(activities) == 1
    assert %{"activity" => 15} in activities
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

  defp query_skeleton(query, query_name) do
    %{
      "operationName" => "#{query_name}",
      "query" => "query #{query_name} #{query}",
      "variables" => "{}"
    }
  end
end