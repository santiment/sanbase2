defmodule Sanbase.Github.GithubApiTest do
  use SanbaseWeb.ConnCase, async: false

  alias Sanbase.Influxdb.Measurement
  alias Sanbase.Github
  alias Sanbase.Model.Project
  alias Sanbase.Repo

  import SanbaseWeb.Graphql.TestHelpers

  setup do
    Github.Store.create_db()

    slug = "santiment"

    %Project{}
    |> Project.changeset(%{name: "Project1", ticker: "SAN", coinmarketcap_id: slug})
    |> Repo.insert!()

    Github.Store.drop_measurement("SAN")
    Github.Store.drop_measurement("TEST1")
    Github.Store.drop_measurement("TEST2")

    datetime1 = DateTime.from_naive!(~N[2017-05-13 15:00:00], "Etc/UTC")
    datetime2 = DateTime.from_naive!(~N[2017-05-13 16:00:00], "Etc/UTC")
    datetime3 = DateTime.from_naive!(~N[2017-05-13 17:00:00], "Etc/UTC")
    datetime4 = DateTime.from_naive!(~N[2017-05-13 18:00:00], "Etc/UTC")
    datetime5 = DateTime.from_naive!(~N[2017-05-13 19:00:00], "Etc/UTC")
    datetime6 = DateTime.from_naive!(~N[2017-05-13 20:00:00], "Etc/UTC")
    dates_interval = "1d"
    datetime_no_activity1 = DateTime.from_naive!(~N[2010-05-13 21:45:00], "Etc/UTC")
    datetime_no_activity2 = DateTime.from_naive!(~N[2010-05-15 21:45:00], "Etc/UTC")

    Github.Store.import([
      %Measurement{
        timestamp: datetime1 |> DateTime.to_unix(:nanoseconds),
        fields: %{activity: 5},
        name: "SAN"
      },
      %Measurement{
        timestamp: datetime2 |> DateTime.to_unix(:nanoseconds),
        fields: %{activity: 10},
        name: "SAN"
      },
      %Measurement{
        timestamp: datetime3 |> DateTime.to_unix(:nanoseconds),
        fields: %{activity: 5},
        name: "SAN"
      },
      %Measurement{
        timestamp: datetime4 |> DateTime.to_unix(:nanoseconds),
        fields: %{activity: 10},
        name: "SAN"
      },
      %Measurement{
        timestamp: datetime5 |> DateTime.to_unix(:nanoseconds),
        fields: %{activity: 20},
        name: "SAN"
      },
      %Measurement{
        timestamp: datetime6 |> DateTime.to_unix(:nanoseconds),
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

    [
      datetime1: datetime1,
      datetime2: datetime2,
      datetime3: datetime3,
      datetime4: datetime4,
      datetime5: datetime5,
      datetime6: datetime6,
      dates_interval: dates_interval,
      datetime_no_activity1: datetime_no_activity1,
      datetime_no_activity2: datetime_no_activity2,
      slug: slug
    ]
  end

  test "fetching github time series data when an interval is not provided", context do
    query = """
    {
      githubActivity(
        slug: "#{context.slug}",
        from: "#{context.datetime1}"
        to: "#{context.datetime6}") {
          activity
        }
    }
    """

    result =
      context.conn
      |> post("/graphql", query_skeleton(query, "githubActivity"))

    activities = json_response(result, 200)["data"]["githubActivity"]

    assert %{"activity" => 60} in activities
  end

  test "fetching github time series data", context do
    query = """
    {
      githubActivity(
        slug: "#{context.slug}",
        from: "#{context.datetime1}",
        interval: "1h") {
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
        slug: "#{context.slug}",
        from: "#{context.datetime1}",
        to: "#{context.datetime6}",
        interval: "#{context.dates_interval}") {
          activity
        }
    }
    """

    result =
      context.conn
      |> post("/graphql", query_skeleton(query, "githubActivity"))

    activities = json_response(result, 200)["data"]["githubActivity"]

    assert Enum.count(activities) == 1
    assert %{"activity" => 60} in activities
  end

  test "retrive all ticker names", context do
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

  test "interval with no activity returns empty result", context do
    query = """
    {
      githubActivity(
        slug: "#{context.slug}",
        from: "#{context.datetime_no_activity1}",
        to: "#{context.datetime_no_activity2}",
        interval: "#{context.dates_interval}") {
          activity
        }
    }
    """

    result =
      context.conn
      |> post("/graphql", query_skeleton(query, "githubActivity"))

    activities = json_response(result, 200)["data"]["githubActivity"]

    assert activities == []
  end

  test "fetch moving average activity", context do
    query = """
    {
      githubActivity(
        slug: "#{context.slug}",
        from: "#{context.datetime1}",
        to: "#{context.datetime6}",
        interval: "1h",
        transform: "movingAverage",
        moving_average_interval_base: "3h") {
          activity
        }
    }
    """

    result =
      context.conn
      |> post("/graphql", query_skeleton(query, "githubActivity"))

    activities = json_response(result, 200)["data"]["githubActivity"]
    assert %{"activity" => 7} in activities
    assert %{"activity" => 9} in activities
    assert %{"activity" => 12} in activities
    assert %{"activity" => 14} in activities
  end
end
