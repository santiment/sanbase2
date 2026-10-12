defmodule SanbaseWeb.Graphql.DashboardCacheParametersOverrideTest do
  # A null or non-object `parametersOverride` (:json arg) must not crash the resolver
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

  for json <- ["null", ~s|"null"|] do
    test "parametersOverride #{json} is treated as no override", context do
      result = execute_query(context.conn, cached_query(context.dashboard_id, unquote(json)))

      refute Map.has_key?(result, "errors")
      assert %{"queries" => []} = get_in(result, ["data", "getCachedDashboardQueriesExecutions"])
    end
  end

  for json <- [~s|"[1, 2]"|, ~s|"\\"abc\\""|, ~s|"42"|] do
    test "non-object parametersOverride #{json} returns a clean error", context do
      result = execute_query(context.conn, cached_query(context.dashboard_id, unquote(json)))

      assert get_in(result, ["data", "getCachedDashboardQueriesExecutions"]) == nil
      assert [%{"message" => message} | _] = result["errors"]
      assert is_binary(message)
    end
  end

  test "anonymous user with null parametersOverride does not crash", context do
    result = execute_query(build_conn(), cached_query(context.dashboard_id, "null"))

    refute Map.has_key?(result, "errors")
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
