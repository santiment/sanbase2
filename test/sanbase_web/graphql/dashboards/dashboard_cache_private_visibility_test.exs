defmodule SanbaseWeb.Graphql.DashboardCachePrivateVisibilityTest do
  # The cache row is created when the owner loads the dashboard, it must stay private after that
  use SanbaseWeb.ConnCase,
    async: false,
    parameterize: [%{viewer: :other_user}, %{viewer: :anonymous}]

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers
  import SanbaseWeb.DashboardsApiHelpers

  test "the cache of a private dashboard is not readable by others", %{viewer: viewer} do
    owner_conn = setup_jwt_auth(build_conn(), insert(:user))

    dashboard_id =
      execute_dashboard_mutation(owner_conn, :create_dashboard, %{
        name: "Private dashboard",
        is_public: false
      })
      |> get_in(["data", "createDashboard", "id"])

    refute Map.has_key?(execute_query(owner_conn, cached_query(dashboard_id)), "errors")

    result = execute_query(viewer_conn(viewer), cached_query(dashboard_id))

    assert get_in(result, ["data", "getCachedDashboardQueriesExecutions"]) == nil
    assert [%{"message" => message}] = result["errors"]
    assert message =~ "the dashboard is private"
  end

  defp viewer_conn(:other_user), do: setup_jwt_auth(build_conn(), insert(:user))
  defp viewer_conn(:anonymous), do: build_conn()

  defp cached_query(dashboard_id) do
    """
    {
      getCachedDashboardQueriesExecutions(dashboardId: #{dashboard_id}) {
        queries { queryId rows }
      }
    }
    """
  end
end
