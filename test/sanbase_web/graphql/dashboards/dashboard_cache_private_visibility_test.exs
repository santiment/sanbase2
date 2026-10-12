defmodule SanbaseWeb.Graphql.DashboardCachePrivateVisibilityTest do
  # The cache of a private dashboard must stay private after its owner has loaded it
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers
  import SanbaseWeb.DashboardsApiHelpers

  setup do
    owner = insert(:user)
    owner_conn = setup_jwt_auth(build_conn(), owner)
    other_conn = setup_jwt_auth(build_conn(), insert(:user))

    dashboard_id =
      execute_dashboard_mutation(owner_conn, :create_dashboard, %{
        name: "Private dashboard",
        is_public: false
      })
      |> get_in(["data", "createDashboard", "id"])

    %{
      owner_conn: owner_conn,
      other_conn: other_conn,
      anonymous_conn: build_conn(),
      dashboard_id: dashboard_id
    }
  end

  test "non-owner cannot read the cache of a private dashboard before the owner did",
       context do
    assert_no_access(context.other_conn, context.dashboard_id)
  end

  for conn_key <- [:other_conn, :anonymous_conn] do
    test "#{conn_key} cannot read the cache of a private dashboard after the owner did",
         context do
      # The owner loading the dashboard creates the cache row
      owner_result = execute_query(context.owner_conn, cached_query(context.dashboard_id))
      refute Map.has_key?(owner_result, "errors")

      assert_no_access(context[unquote(conn_key)], context.dashboard_id)
    end
  end

  defp assert_no_access(conn, dashboard_id) do
    result = execute_query(conn, cached_query(dashboard_id))

    assert get_in(result, ["data", "getCachedDashboardQueriesExecutions"]) == nil
    assert [%{"message" => _} | _] = result["errors"]
  end

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
