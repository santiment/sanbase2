defmodule Sanbase.Github.TwitterApiTest do
  use SanbaseWeb.ConnCase
  use Phoenix.ConnTest

  alias Sanbase.Influxdb.Measurement
  alias Sanbase.ExternalServices.TwitterData.Store
  alias Sanbase.Repo
  alias Sanbase.Model.Project

  setup do
    Store.create_db()
    Store.drop_measurement("SAN")
    Store.drop_measurement("TEST1")
    Store.drop_measurement("TEST2")

    datetime1 = DateTime.from_naive!(~N[2017-05-13 18:00:00], "Etc/UTC")
    datetime2 = DateTime.from_naive!(~N[2017-05-14 18:00:00], "Etc/UTC")
    datetime3 = DateTime.from_naive!(~N[2017-05-15 18:00:00], "Etc/UTC")

    datetime_no_activity1 = DateTime.from_naive!(~N[2010-05-13 18:00:00], "Etc/UTC")
    datetime_no_activity2 = DateTime.from_naive!(~N[2010-05-15 18:00:00], "Etc/UTC")

    %Project{}
    |> Project.changeset(%{
      name: "Santiment",
      ticker: "SAN",
      twitter_link: "https://twitter.com/santimentfeed"
    })
    |> Repo.insert!()

    %Project{}
    |> Project.changeset(%{
      name: "TestProj",
      ticker: "TEST1",
      twitter_link: "https://twitter.com/some_test_acc"
    })

    Store.import([
      %Measurement{
        timestamp: datetime1 |> DateTime.to_unix(:nanoseconds),
        fields: %{followers_count: 500},
        name: "santimentfeed"
      },
      %Measurement{
        timestamp: datetime2 |> DateTime.to_unix(:nanoseconds),
        fields: %{followers_count: 1000},
        name: "santimentfeed"
      },
      %Measurement{
        timestamp: datetime3 |> DateTime.to_unix(:nanoseconds),
        fields: %{followers_count: 1500},
        name: "santimentfeed"
      },
      %Measurement{
        timestamp: datetime2 |> DateTime.to_unix(:nanoseconds),
        fields: %{followers_count: 5},
        name: "some_test_acc"
      },
      %Measurement{
        timestamp: datetime3 |> DateTime.to_unix(:nanoseconds),
        fields: %{followers_count: 10},
        name: "some_test_acc  "
      }
    ])

    [
      datetime1: datetime1,
      datetime2: datetime2,
      datetime3: datetime3,
      datetime_no_activity1: datetime_no_activity1,
      datetime_no_activity2: datetime_no_activity2
    ]
  end

  test "fetching last twitter data", context do
    query = """
    {
      twitterData(
        ticker: "SAN") {
          twitterName
          followersCount
        }
    }
    """

    result =
      context.conn
      |> post("/graphql", query_skeleton(query, "twitterData"))

    twitter_data = json_response(result, 200)["data"]["twitterData"]

    assert twitter_data["followersCount"] == 1500
    assert twitter_data["twitterName"] == "santimentfeed"
  end

  test "fetch history twitter data", context do
    query = """
    {
      historyTwitterData(
        ticker: "SAN",
        from: "#{context.datetime1}",
        to: "#{context.datetime3}"){
          followersCount
        }
    }
    """

    result =
      context.conn
      |> post("/graphql", query_skeleton(query, "historyTwitterData"))

    history_twitter_data = json_response(result, 200)["data"]["historyTwitterData"]

    assert %{"followersCount" => 500} in history_twitter_data
    assert %{"followersCount" => 1000} in history_twitter_data
    assert %{"followersCount" => 1500} in history_twitter_data
  end

  defp query_skeleton(query, query_name) do
    %{
      "operationName" => "#{query_name}",
      "query" => "query #{query_name} #{query}",
      "variables" => "{}"
    }
  end
end