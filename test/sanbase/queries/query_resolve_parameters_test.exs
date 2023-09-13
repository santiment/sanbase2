defmodule Sanbase.Queries.ResolveParametersTest do
  use SanbaseWeb.ConnCase, async: true

  import Sanbase.Factory

  setup do
    user = insert(:user)

    # Create a dashboard and a query
    assert {:ok, dashboard} = Sanbase.Dashboards.create_dashboard(%{name: "Dashboard"}, user.id)

    assert {:ok, query} =
             Sanbase.Queries.create_query(
               %{
                 sql_query_text: "SELECT * FROM metrics WHERE slug = {{slug}} LIMIT {{limit}}",
                 sql_query_parameters: %{"slug" => "ethereum", "limit" => 20}
               },
               user.id
             )

    # Add the query to the dashboard
    assert {:ok, dashboard_query_mapping} =
             Sanbase.Dashboards.add_query_to_dashboard(dashboard.id, query.id, user.id)

    # Add a global parameter to the dashboard
    assert {:ok, dashboard} =
             Sanbase.Dashboards.add_global_parameter(dashboard.id, user.id,
               key: "slug",
               value: "bitcoin"
             )

    # Make the global paramter override the query local paramter
    assert {:ok, dashboard} =
             Sanbase.Dashboards.add_global_parameter_override(
               dashboard.id,
               dashboard_query_mapping.id,
               user.id,
               global: "slug",
               local: "slug"
             )

    %{
      user: user,
      dashboard: dashboard,
      query: query,
      dashboard_query_mapping: dashboard_query_mapping
    }
  end

  test "resolve parameters", context do
    %{dashboard: dashboard, dashboard_query_mapping: dashboard_query_mapping, user: user} =
      context

    # Check that when `get_dashboard_query/3` is called, the global parameter
    # has overriden the local one. `get_dashboard_query/3` is responsible
    # for resolving the paramters, while just `get_query/2` is not.
    assert {:ok, fetched_dashboard_query} =
             Sanbase.Queries.get_dashboard_query(
               dashboard.id,
               dashboard_query_mapping.id,
               user.id
             )

    assert fetched_dashboard_query.sql_query_text ==
             "SELECT * FROM metrics WHERE slug = {{slug}} LIMIT {{limit}}"

    assert fetched_dashboard_query.sql_query_parameters == %{
             "slug" => "bitcoin",
             "limit" => 20
           }
  end

  test "update global parameter", context do
    %{dashboard: dashboard, dashboard_query_mapping: dashboard_query_mapping, user: user} =
      context

    # Update the global parameter value and key.
    # Updating the key name will not affect
    # anything in the queries, it is just used to refer to the global parameter
    # in the API and show its name in the frotnend. The key name in the query itself
    # still has the old name, as it should.
    assert {:ok, _} =
             Sanbase.Dashboards.update_global_parameter(dashboard.id, user.id,
               key: "slug",
               new_key: "slug_new_key",
               new_value: "xrp"
             )

    assert {:ok, fetched_dashboard_query} =
             Sanbase.Queries.get_dashboard_query(
               dashboard.id,
               dashboard_query_mapping.id,
               user.id
             )

    assert fetched_dashboard_query.sql_query_parameters == %{
             "slug" => "xrp",
             "limit" => 20
           }
  end

  test "delete global parameter override", context do
    %{dashboard: dashboard, dashboard_query_mapping: dashboard_query_mapping, user: user} =
      context

    # Delete the paramter override
    assert {:ok, _} =
             Sanbase.Dashboards.delete_global_parameter_override(
               dashboard.id,
               dashboard_query_mapping.id,
               user.id,
               "slug"
             )

    assert {:ok, fetched_dashboard_query} =
             Sanbase.Queries.get_dashboard_query(
               dashboard.id,
               dashboard_query_mapping.id,
               user.id
             )

    # No longer resolves to bitcoin
    assert fetched_dashboard_query.sql_query_parameters == %{
             "slug" => "ethereum",
             "limit" => 20
           }
  end

  test "delete global parameter", context do
    %{dashboard: dashboard, dashboard_query_mapping: dashboard_query_mapping, user: user} =
      context

    # Delete the paramter override
    assert {:ok, _} =
             Sanbase.Dashboards.delete_global_parameter(
               dashboard.id,
               user.id,
               "slug"
             )

    assert {:ok, fetched_dashboard_query} =
             Sanbase.Queries.get_dashboard_query(
               dashboard.id,
               dashboard_query_mapping.id,
               user.id
             )

    # No longer resolves to bitcoin
    assert fetched_dashboard_query.sql_query_parameters == %{
             "slug" => "ethereum",
             "limit" => 20
           }
  end
end
