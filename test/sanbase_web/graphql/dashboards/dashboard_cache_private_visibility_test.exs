defmodule SanbaseWeb.Graphql.DashboardCachePrivateVisibilityTest do
  # Found while investigating SANBASE-BACKEND-PROD-GAX.
  # DashboardCache.by_dashboard_id/4 checks dashboard visibility only when it
  # creates a new cache row (new/3). Once the owner has loaded their private
  # dashboard, the cache row exists and any user (including anonymous ones)
  # can read it via getCachedDashboardQueriesExecutions.
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers
  import SanbaseWeb.DashboardsApiHelpers

  setup do
    owner = insert(:user)
    owner_conn = setup_jwt_auth(build_conn(), owner)

    other_user = insert(:user)
    other_conn = setup_jwt_auth(build_conn(), other_user)

    dashboard_id =
      execute_dashboard_mutation(owner_conn, :create_dashboard, %{
        name: "Private dashboard",
        is_public: false
      })
      |> get_in(["data", "createDashboard", "id"])

    %{owner_conn: owner_conn, other_conn: other_conn, dashboard_id: dashboard_id}
  end

  test "non-owner cannot read the cache of a private dashboard before the owner did",
       context do
    result = get_cached(context.other_conn, context.dashboard_id)

    assert get_in(result, ["data", "getCachedDashboardQueriesExecutions"]) == nil
    assert [%{"message" => _} | _] = result["errors"]
  end

  test "non-owner cannot read the cache of a private dashboard after the owner did",
       context do
    # The owner loading the dashboard creates the cache row
    owner_result = get_cached(context.owner_conn, context.dashboard_id)
    refute Map.has_key?(owner_result, "errors")

    result = get_cached(context.other_conn, context.dashboard_id)

    assert get_in(result, ["data", "getCachedDashboardQueriesExecutions"]) == nil
    assert [%{"message" => _} | _] = result["errors"]
  end

  test "anonymous user cannot read the cache of a private dashboard after the owner did",
       context do
    owner_result = get_cached(context.owner_conn, context.dashboard_id)
    refute Map.has_key?(owner_result, "errors")

    result = get_cached(build_conn(), context.dashboard_id)

    assert get_in(result, ["data", "getCachedDashboardQueriesExecutions"]) == nil
    assert [%{"message" => _} | _] = result["errors"]
  end

  defp get_cached(conn, dashboard_id) do
    query = """
    {
      getCachedDashboardQueriesExecutions(dashboardId: #{dashboard_id}) {
        queries { queryId rows }
      }
    }
    """

    conn
    |> post("/graphql", query_skeleton(query))
    |> json_response(200)
  end
end
