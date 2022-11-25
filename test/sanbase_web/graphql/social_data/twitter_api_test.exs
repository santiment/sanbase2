defmodule Sanbase.Github.TwitterApiTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  setup do
    # All tests implicitly test for when more than one record has the same ticker
    project = insert(:random_project)
    _ = insert(:random_project, ticker: project.ticker)

    %{
      project: project,
      dt1: ~U[2017-05-13 00:00:00Z],
      dt2: ~U[2017-05-14 00:00:00Z],
      dt3: ~U[2017-05-15 00:00:00Z]
    }
  end

  def get_current_twitter_followers(conn, slug) do
    query = """
    {
      twitterData(slug: "#{slug}") {
        followersCount
      }
    }
    """

    conn
    |> post("/graphql", query_skeleton(query, "twitterData"))
    |> json_response(200)
  end

  defp get_twitter_followers(conn, slug, from, to, interval) do
    query = """
    {
      getMetric(metric: "twitter_followers") {
          timeseriesData(
            slug: "#{slug}"
            from: "#{from}"
            to: "#{to}"
            interval: "#{interval}"
          ){
            datetime
            value
          }
        }
    }
    """

    conn
    |> post("/graphql", query_skeleton(query, "getMetric"))
    |> json_response(200)
  end

  test "fetch current twitter followers", context do
    %{dt1: dt, project: project, conn: conn} = context

    Sanbase.Mock.prepare_mock2(&Sanbase.ClickhouseRepo.query/2, {:ok, %{rows: [[dt, 1000]]}})
    |> Sanbase.Mock.run_with_mocks(fn ->
      result =
        get_current_twitter_followers(conn, project.slug)
        |> get_in(["data", "twitterData", "followersCount"])

      assert result == 1000
    end)
  end

  test "fetching timeseries twitter followers", context do
    %{dt1: dt1, dt2: dt2, dt3: dt3, project: project, conn: conn} = context

    rows = [
      [DateTime.to_unix(dt1), 11_437],
      [DateTime.to_unix(dt2), 11_434],
      [DateTime.to_unix(dt3), 11_439]
    ]

    Sanbase.Mock.prepare_mock2(&Sanbase.ClickhouseRepo.query/2, {:ok, %{rows: rows}})
    |> Sanbase.Mock.run_with_mocks(fn ->
      result =
        get_twitter_followers(conn, project.slug, dt1, dt3, "1d")
        |> get_in(["data", "getMetric", "timeseriesData"])

      assert result == [
               %{"datetime" => dt1 |> DateTime.to_iso8601(), "value" => 11_437.0},
               %{"datetime" => dt2 |> DateTime.to_iso8601(), "value" => 11_434.0},
               %{"datetime" => dt3 |> DateTime.to_iso8601(), "value" => 11_439.0}
             ]
    end)
  end

  test "fetching last twitter data for a project with invalid twitter link", context do
    %{conn: conn, project: project} = context

    Sanbase.Project.changeset(project, %{twitter_link: "santiment"})
    |> Sanbase.Repo.update!()

    result =
      get_current_twitter_followers(conn, project.slug)
      |> get_in(["data", "twitterData"])

    assert result == nil
  end
end
