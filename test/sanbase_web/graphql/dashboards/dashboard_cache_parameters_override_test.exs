defmodule SanbaseWeb.Graphql.DashboardCacheParametersOverrideTest do
  # Reproduces SANBASE-BACKEND-PROD-GAX: getCachedDashboardQueriesExecutions
  # passes the `parametersOverride` :json arg straight to
  # DashboardCache.hash_parameters/1, which only has map clauses. An explicit
  # `null` or any non-object JSON value raises FunctionClauseError (500).
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers
  import SanbaseWeb.DashboardsApiHelpers

  setup do
    user = insert(:user)
    conn = setup_jwt_auth(build_conn(), user)

    dashboard_id =
      execute_dashboard_mutation(conn, :create_dashboard)
      |> get_in(["data", "createDashboard", "id"])

    %{conn: conn, dashboard_id: dashboard_id}
  end

  test "explicit null parametersOverride is treated as no override", context do
    result = get_cached(context.conn, context.dashboard_id, "null")

    refute Map.has_key?(result, "errors")
    assert %{"queries" => []} = get_in(result, ["data", "getCachedDashboardQueriesExecutions"])
  end

  test "JSON 'null' string parametersOverride is treated as no override", context do
    result = get_cached(context.conn, context.dashboard_id, ~s|"null"|)

    refute Map.has_key?(result, "errors")
    assert %{"queries" => []} = get_in(result, ["data", "getCachedDashboardQueriesExecutions"])
  end

  for json <- [~s|"[1, 2]"|, ~s|"\\"abc\\""|, ~s|"42"|] do
    test "non-object parametersOverride #{json} returns a clean error", context do
      result = get_cached(context.conn, context.dashboard_id, unquote(json))

      assert get_in(result, ["data", "getCachedDashboardQueriesExecutions"]) == nil
      assert [%{"message" => message} | _] = result["errors"]
      assert is_binary(message)
    end
  end

  test "anonymous user with null parametersOverride does not crash", context do
    result = get_cached(build_conn(), context.dashboard_id, "null")

    refute Map.has_key?(result, "errors")
  end

  defp get_cached(conn, dashboard_id, parameters_override) do
    query = """
    {
      getCachedDashboardQueriesExecutions(
        dashboardId: #{dashboard_id}
        parametersOverride: #{parameters_override}
      ) {
        queries { queryId }
      }
    }
    """

    conn
    |> post("/graphql", query_skeleton(query))
    |> json_response(200)
  end
end
