defmodule SanbaseWeb.Graphql.DashboardCacheParametersOverrideTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers
  import SanbaseWeb.DashboardsApiHelpers

  setup do
    conn = setup_jwt_auth(build_conn(), insert(:user))

    dashboard_id =
      execute_dashboard_mutation(conn, :create_dashboard)
      |> get_in(["data", "createDashboard", "id"])

    %{conn: conn, dashboard_id: dashboard_id}
  end

  test "a null parametersOverride is treated as no override", context do
    result = execute_query(context.conn, cached_query(context.dashboard_id, "null"))

    refute Map.has_key?(result, "errors")
    assert %{"queries" => []} = get_in(result, ["data", "getCachedDashboardQueriesExecutions"])
  end

  test "a non-object parametersOverride returns an error", context do
    query = cached_query(context.dashboard_id, ~s|"[1, 2]"|)

    assert execute_query_with_error(context.conn, query) ==
             "parametersOverride must be a JSON object"
  end

  defp cached_query(dashboard_id, parameters_override) do
    """
    {
      getCachedDashboardQueriesExecutions(
        dashboardId: #{dashboard_id}
        parametersOverride: #{parameters_override}
      ) {
        queries { queryId }
      }
    }
    """
  end
end
