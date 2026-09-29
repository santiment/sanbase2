defmodule SanbaseWeb.Graphql.GithubActivityV2ApiTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  setup do
    project = insert(:random_project, %{github_organizations: [build(:github_organization)]})
    # Version 2.0 is not available to anonymous requests
    conn = setup_jwt_auth(build_conn(), insert(:user))

    %{conn: conn, project: project}
  end

  for metric <- ["dev_activity", "github_activity"] do
    test "getMetric #{metric} version 2.0 with a slug selector", %{conn: conn, project: project} do
      rows = [
        [DateTime.to_unix(~U[2026-05-01 00:00:00Z]), 4333.25],
        [DateTime.to_unix(~U[2026-06-01 00:00:00Z]), 4448.5]
      ]

      Sanbase.Mock.prepare_mock2(&Sanbase.ClickhouseRepo.query/3, {:ok, %{rows: rows}})
      |> Sanbase.Mock.run_with_mocks(fn ->
        query = """
        {
          getMetric(metric: "#{unquote(metric)}", version: "2.0") {
            timeseriesDataJson(
              from: "2026-05-01T00:00:00Z"
              to: "2026-07-01T00:00:00Z"
              selector: {slug: "#{project.slug}"}
              interval: "toStartOfMonth"
              cachingParams: {baseTtl: 1, maxTtlOffset: 1}
            )
          }
        }
        """

        result = execute_query(conn, query, "getMetric")

        assert result == %{
                 "timeseriesDataJson" => [
                   %{"datetime" => "2026-05-01T00:00:00Z", "value" => 4333.25},
                   %{"datetime" => "2026-06-01T00:00:00Z", "value" => 4448.5}
                 ]
               }
      end)
    end
  end

  test "getMetric dev_activity version 2.0 with an organization selector", %{conn: conn} do
    rows = [[DateTime.to_unix(~U[2026-06-08 00:00:00Z]), 230.4]]

    Sanbase.Mock.prepare_mock2(&Sanbase.ClickhouseRepo.query/3, {:ok, %{rows: rows}})
    |> Sanbase.Mock.run_with_mocks(fn ->
      query = """
      {
        getMetric(metric: "dev_activity", version: "2.0") {
          timeseriesDataJson(
            from: "2026-06-08T00:00:00Z"
            to: "2026-06-09T00:00:00Z"
            selector: {organization: "ethereum"}
            interval: "1d"
          )
        }
      }
      """

      result = execute_query(conn, query, "getMetric")

      assert result == %{
               "timeseriesDataJson" => [%{"datetime" => "2026-06-08T00:00:00Z", "value" => 230.4}]
             }
    end)
  end

  test "availableVersions of dev_activity", %{conn: conn} do
    query = """
    {
      getMetric(metric: "dev_activity") {
        metadata { availableVersions { versionNum } }
      }
    }
    """

    result = execute_query(conn, query, "getMetric")

    assert result == %{
             "metadata" => %{
               "availableVersions" => [%{"versionNum" => "1.0"}, %{"versionNum" => "2.0"}]
             }
           }
  end
end
