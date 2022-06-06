defmodule SanbaseWeb.Graphql.DashboardApiTest do
  use SanbaseWeb.ConnCase, async: true

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  setup do
    user = insert(:user)
    conn = setup_jwt_auth(build_conn(), user)

    %{conn: conn, user: user}
  end

  describe "create/update/delete dashboard" do
    test "create", context do
      result =
        execute_dashboard_mutation(context.conn, :create_dashboard, %{
          name: "MyDashboard",
          description: "some text",
          is_public: true
        })
        |> get_in(["data", "createDashboard"])

      user_id = context.user.id |> to_string()

      assert %{
               "name" => "MyDashboard",
               "description" => "some text",
               "panels" => [],
               "user" => %{"id" => ^user_id}
             } = result
    end

    test "update", context do
      dashboard_id =
        execute_dashboard_mutation(context.conn, :create_dashboard)
        |> get_in(["data", "createDashboard", "id"])

      result =
        execute_dashboard_mutation(context.conn, :update_dashboard, %{
          id: dashboard_id,
          name: "MyDashboard - update",
          description: "some text - update",
          is_public: false
        })
        |> get_in(["data", "updateDashboard"])

      user_id = context.user.id |> to_string()

      assert %{
               "id" => ^dashboard_id,
               "name" => "MyDashboard - update",
               "description" => "some text - update",
               "panels" => [],
               "user" => %{"id" => ^user_id}
             } = result
    end

    test "delete", context do
      dashboard_id =
        execute_dashboard_mutation(context.conn, :create_dashboard)
        |> get_in(["data", "createDashboard", "id"])

      execute_dashboard_mutation(context.conn, :remove_dashboard, %{id: dashboard_id})

      assert {:error, error_msg} = Sanbase.Dashboard.load_schema(dashboard_id)
      assert error_msg =~ "does not exist"
    end
  end

  describe "create/update/delete panels" do
    test "create panel", context do
      dashboard_id =
        execute_dashboard_mutation(context.conn, :create_dashboard)
        |> get_in(["data", "createDashboard", "id"])

      result =
        execute_dashboard_panel_mutation(context.conn, :create_dashboard_panel, %{
          dashboard_id: dashboard_id,
          panel: %{
            map_as_input_object: true,
            name: "My Panel",
            sql: %{
              map_as_input_object: true,
              query:
                "SELECT * FROM intraday_metrics WHERE asset_id IN (SELECT asset_id FROM asset_metadata WHERE name = ?2 LIMIT ?1)",
              args: Jason.encode!([20, "bitcoin"])
            }
          }
        })
        |> get_in(["data", "createDashboardPanel"])

      assert %{
               "id" => binary_id,
               "dashboardId" => ^dashboard_id,
               "sql" => %{
                 "args" => [20, "bitcoin"],
                 "query" =>
                   "SELECT * FROM intraday_metrics WHERE asset_id IN (SELECT asset_id FROM asset_metadata WHERE name = ?2 LIMIT ?1)"
               }
             } = result

      assert is_binary(binary_id)
    end

    test "update panel", context do
      dashboard_id =
        execute_dashboard_mutation(context.conn, :create_dashboard)
        |> get_in(["data", "createDashboard", "id"])

      panel =
        execute_dashboard_panel_mutation(context.conn, :create_dashboard_panel, %{
          dashboard_id: dashboard_id,
          panel: %{
            map_as_input_object: true,
            name: "p",
            sql: %{map_as_input_object: true, query: "SELECT now()", args: Jason.encode!([])}
          }
        })
        |> get_in(["data", "createDashboardPanel"])

      updated_panel =
        execute_dashboard_panel_mutation(context.conn, :update_dashboard_panel, %{
          dashboard_id: dashboard_id,
          panel_id: panel["id"],
          panel: %{
            map_as_input_object: true,
            name: "New name",
            sql: %{
              map_as_input_object: true,
              query: "SELECT * FROM intraday_metrics LIMIT ?1",
              args: Jason.encode!([20])
            }
          }
        })
        |> get_in(["data", "updateDashboardPanel"])

      assert %{
               "id" => panel["id"],
               "dashboardId" => dashboard_id,
               "sql" => %{
                 "args" => [20],
                 "query" => "SELECT * FROM intraday_metrics LIMIT ?1"
               }
             } == updated_panel
    end
  end

  defp execute_dashboard_panel_mutation(conn, mutation, args) do
    mutation_name = mutation |> Inflex.camelize(:lower)

    mutation = """
    mutation {
      #{mutation_name}(#{map_to_args(args)}){
        id
        dashboardId
        sql {
          query
          args
        }
      }
    }
    """

    conn
    |> post("/graphql", mutation_skeleton(mutation))
    |> json_response(200)
  end

  defp execute_dashboard_mutation(conn, mutation, args \\ nil) do
    args =
      args ||
        %{
          name: "MyDashboard",
          description: "some text",
          is_public: true
        }

    mutation_name = mutation |> Inflex.camelize(:lower)

    mutation = """
    mutation {
      #{mutation_name}(#{map_to_args(args)}){
        id
        name
        description
        user{ id }
        panels { id }
      }
    }
    """

    conn
    |> post("/graphql", mutation_skeleton(mutation))
    |> json_response(200)
  end
end
