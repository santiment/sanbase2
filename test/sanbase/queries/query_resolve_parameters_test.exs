defmodule Sanbase.Queries.ResolveParametersTest do
  use SanbaseWeb.ConnCase, async: true

  import Sanbase.Factory

  test "resolve parameters" do
    user = insert(:user)

    assert {:ok, dashboard} = Sanbase.Dashboards.create_dashboard(%{name: "Dashboard"}, user.id)

    assert {:ok, query} =
             Sanbase.Queries.create_query(
               %{
                 sql_query_text: "SELECT * FROM metrics WHERE slug = {{slug}} LIMIT {{limit}}",
                 sql_parameters: %{"slug" => "ethereum", "limit" => 20}
               },
               user.id
             )

    assert {:ok, dashboard_query_mapping} =
             Sanbase.Dashboards.add_query_to_dashboard(dashboard.id, query.id, user.id)

    assert {:ok, dashboard} =
             Sanbase.Dashboards.put_global_parameter(dashboard.id, user.id,
               key: "slug",
               value: "bitcoin"
             )

    assert {:ok, dashboard} =
             Sanbase.Dashboards.put_global_parameter_override(
               dashboard.id,
               dashboard_query_mapping.id,
               user.id,
               global: "slug",
               local: "slug"
             )

    assert {:ok, fetched_dashboard_query} =
             Sanbase.Queries.get_dashboard_query(
               dashboard.id,
               dashboard_query_mapping.id,
               user.id
             )

    assert fetched_dashboard_query.sql_query_text ==
             "SELECT * FROM metrics WHERE slug = {{slug}} LIMIT {{limit}}"

    assert fetched_dashboard_query.sql_parameters == %{
             "slug" => "bitcoin",
             "limit" => 20
           }

    assert {:ok, fetched_query} =
             Sanbase.Queries.get_dashboard_query(
               dashboard.id,
               dashboard_query_mapping.id,
               user.id
             )

    assert fetched_query.sql_query_text ==
             "SELECT * FROM metrics WHERE slug = {{slug}} LIMIT {{limit}}"

    assert fetched_query.sql_parameters == %{
             "slug" => "bitcoin",
             "limit" => 20
           }
  end
end
