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
        execute_dashboard_panel_schema_mutation(
          context.conn,
          :create_dashboard_panel,
          default_dashboard_panel_args() |> Map.put(:dashboard_id, dashboard_id)
        )
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
        execute_dashboard_panel_schema_mutation(
          context.conn,
          :create_dashboard_panel,
          default_dashboard_panel_args() |> Map.put(:dashboard_id, dashboard_id)
        )
        |> get_in(["data", "createDashboardPanel"])

      updated_panel =
        execute_dashboard_panel_schema_mutation(context.conn, :update_dashboard_panel, %{
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

    test "delete panel", context do
      dashboard =
        execute_dashboard_mutation(context.conn, :create_dashboard)
        |> get_in(["data", "createDashboard"])

      assert dashboard["panels"] == []

      panel =
        execute_dashboard_panel_schema_mutation(
          context.conn,
          :create_dashboard_panel,
          default_dashboard_panel_args() |> Map.put(:dashboard_id, dashboard["id"])
        )
        |> get_in(["data", "createDashboardPanel"])

      dashboard =
        get_dashboard_schema(context.conn, dashboard["id"])
        |> get_in(["data", "getDashboardSchema"])

      assert dashboard["panels"] == [%{"id" => panel["id"]}]

      execute_dashboard_panel_schema_mutation(context.conn, :remove_dashboard_panel, %{
        dashboard_id: dashboard["id"],
        panel_id: panel["id"]
      })

      dashboard =
        get_dashboard_schema(context.conn, dashboard["id"])
        |> get_in(["data", "getDashboardSchema"])

      assert dashboard["panels"] == []
    end
  end

  describe "compute and get cache" do
    defp panel_mocked_clickhouse_query() do
      %Clickhousex.Result{
        columns: ["asset_id", "metric_id", "dt", "value", "computed_at"],
        command: :selected,
        num_rows: 2,
        query_id: "177a5a3d-072b-48ac-8cf5-d8375c8314ef",
        rows: [
          [2503, 250, ~N[2008-12-10 00:00:00], 0.0, ~N[2020-02-28 15:18:42]],
          [2503, 250, ~N[2008-12-10 00:05:00], 0.0, ~N[2020-02-28 15:18:42]]
        ],
        summary: %{
          "read_bytes" => "0",
          "read_rows" => "0",
          "total_rows_to_read" => "0",
          "written_bytes" => "0",
          "written_rows" => "0"
        }
      }
    end

    test "compute a panel", context do
      dashboard =
        execute_dashboard_mutation(context.conn, :create_dashboard)
        |> get_in(["data", "createDashboard"])

      panel =
        execute_dashboard_panel_schema_mutation(
          context.conn,
          :create_dashboard_panel,
          default_dashboard_panel_args() |> Map.put(:dashboard_id, dashboard["id"])
        )
        |> get_in(["data", "createDashboardPanel"])

      Sanbase.Mock.prepare_mock2(
        &Sanbase.ClickhouseRepo.query/2,
        {:ok, panel_mocked_clickhouse_query()}
      )
      |> Sanbase.Mock.run_with_mocks(fn ->
        result =
          execute_dashboard_panel_cache_mutation(context.conn, :compute_dashboard_panel, %{
            dashboard_id: dashboard["id"],
            panel_id: panel["id"]
          })

        dashboard_id = dashboard["id"]

        assert %{
                 "data" => %{
                   "computeDashboardPanel" => %{
                     "columnNames" => ["asset_id", "metric_id", "dt", "value", "computed_at"],
                     "dashboardId" => ^dashboard_id,
                     "id" => _,
                     "rows" => [
                       [2503, 250, "2008-12-10T00:00:00Z", 0.0, "2020-02-28T15:18:42Z"],
                       [2503, 250, "2008-12-10T00:05:00Z", 0.0, "2020-02-28T15:18:42Z"]
                     ],
                     "summary" => %{
                       "read_bytes" => "0",
                       "read_rows" => "0",
                       "total_rows_to_read" => "0",
                       "written_bytes" => "0",
                       "written_rows" => "0"
                     },
                     "updatedAt" => updated_at
                   }
                 }
               } = result

        updated_at = Sanbase.DateTimeUtils.from_iso8601!(updated_at)
        assert Sanbase.TestUtils.datetime_close_to(Timex.now(), updated_at, 2, :seconds)
      end)
    end

    test "compute and store a panel", context do
      dashboard =
        execute_dashboard_mutation(context.conn, :create_dashboard)
        |> get_in(["data", "createDashboard"])

      panel =
        execute_dashboard_panel_schema_mutation(
          context.conn,
          :create_dashboard_panel,
          default_dashboard_panel_args() |> Map.put(:dashboard_id, dashboard["id"])
        )
        |> get_in(["data", "createDashboardPanel"])

      Sanbase.Mock.prepare_mock2(
        &Sanbase.ClickhouseRepo.query/2,
        {:ok, panel_mocked_clickhouse_query()}
      )
      |> Sanbase.Mock.run_with_mocks(fn ->
        result =
          execute_dashboard_panel_cache_mutation(
            context.conn,
            :compute_and_store_dashboard_panel,
            %{
              dashboard_id: dashboard["id"],
              panel_id: panel["id"]
            }
          )
          |> get_in(["data", "computeAndStoreDashboardPanel"])

        dashboard_id = dashboard["id"]

        assert %{
                 "columnNames" => ["asset_id", "metric_id", "dt", "value", "computed_at"],
                 "dashboardId" => ^dashboard_id,
                 "id" => id,
                 "rows" => [
                   [2503, 250, "2008-12-10T00:00:00Z", 0.0, "2020-02-28T15:18:42Z"],
                   [2503, 250, "2008-12-10T00:05:00Z", 0.0, "2020-02-28T15:18:42Z"]
                 ],
                 "summary" => %{
                   "read_bytes" => "0",
                   "read_rows" => "0",
                   "total_rows_to_read" => "0",
                   "written_bytes" => "0",
                   "written_rows" => "0"
                 },
                 "updatedAt" => updated_at
               } = result

        assert is_binary(id) and String.length(id) == 36
        updated_at = Sanbase.DateTimeUtils.from_iso8601!(updated_at)
        assert Sanbase.TestUtils.datetime_close_to(Timex.now(), updated_at, 2, :seconds)
      end)

      # Run the next part outside the mock, so if there's data it's not coming from Clickhouse

      dashboard_cache =
        get_dashboard_cache(context.conn, dashboard["id"])
        |> get_in(["data", "getDashboardCache"])

      dashboard_id = dashboard["id"]

      assert %{
               "panels" => [
                 %{
                   "columnNames" => ["asset_id", "metric_id", "dt", "value", "computed_at"],
                   "dashboardId" => ^dashboard_id,
                   "id" => id,
                   "rows" => [
                     [2503, 250, "2008-12-10T00:00:00Z", 0.0, "2020-02-28T15:18:42Z"],
                     [2503, 250, "2008-12-10T00:05:00Z", 0.0, "2020-02-28T15:18:42Z"]
                   ],
                   "summary" => %{
                     "read_bytes" => "0",
                     "read_rows" => "0",
                     "total_rows_to_read" => "0",
                     "written_bytes" => "0",
                     "written_rows" => "0"
                   },
                   "updatedAt" => updated_at
                 }
               ]
             } = dashboard_cache

      assert is_binary(id) and String.length(id) == 36
      updated_at = Sanbase.DateTimeUtils.from_iso8601!(updated_at)
      assert Sanbase.TestUtils.datetime_close_to(Timex.now(), updated_at, 2, :seconds)
    end
  end

  defp execute_dashboard_panel_schema_mutation(conn, mutation, args) do
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

  defp execute_dashboard_panel_cache_mutation(conn, mutation, args) do
    mutation_name = mutation |> Inflex.camelize(:lower)

    mutation = """
    mutation {
      #{mutation_name}(#{map_to_args(args)}){
        id
        dashboardId
        columnNames
        rows
        summary
        updatedAt
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

  defp get_dashboard_schema(conn, dashboard_id) do
    query = """
    {
      getDashboardSchema(id: #{dashboard_id}){
        id
        name
        description
        isPublic
        panels { id }
      }
    }
    """

    conn
    |> post("/graphql", query_skeleton(query))
    |> json_response(200)
  end

  defp get_dashboard_cache(conn, dashboard_id) do
    query = """
    {
      getDashboardCache(id: #{dashboard_id}){
        panels{
          id
          dashboardId
          columnNames
          rows
          summary
          updatedAt
        }
      }
    }
    """

    conn
    |> post("/graphql", query_skeleton(query))
    |> json_response(200)
  end

  defp default_dashboard_panel_args() do
    %{
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
    }
  end
end
