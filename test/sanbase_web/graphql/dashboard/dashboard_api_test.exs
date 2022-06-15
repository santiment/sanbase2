defmodule SanbaseWeb.Graphql.DashboardApiTest do
  use SanbaseWeb.ConnCase, async: false

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
                 "parameters" => %{"limit" => 20, "slug" => "bitcoin"},
                 "query" =>
                   "SELECT * FROM intraday_metrics WHERE asset_id IN (SELECT asset_id FROM asset_metadata WHERE name = {{slug}} LIMIT {{limit}})"
               }
             } = result

      assert is_binary(binary_id)
    end

    test "create panel - error invalid query", context do
      dashboard_id =
        execute_dashboard_mutation(context.conn, :create_dashboard)
        |> get_in(["data", "createDashboard", "id"])

      error_msg =
        execute_dashboard_panel_schema_mutation(
          context.conn,
          :create_dashboard_panel,
          default_dashboard_panel_args()
          |> Map.put(:dashboard_id, dashboard_id)
          |> put_in([:panel, :sql, :query], "SELECT * FROM system.query_log")
        )
        |> get_in(["errors", Access.at(0), "message"])

      assert error_msg == "{\"sql\":[\"system tables are not allowed\"]}"

      error_msg =
        execute_dashboard_panel_schema_mutation(
          context.conn,
          :create_dashboard_panel,
          default_dashboard_panel_args()
          |> Map.put(:dashboard_id, dashboard_id)
          |> put_in([:panel, :sql, :query], "SELECT * FROM non_existing")
        )
        |> get_in(["errors", Access.at(0), "message"])

      assert error_msg == "{\"sql\":[\"table non_existing is not allowed or does not exist\"]}"
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
              query: "SELECT * FROM intraday_metrics LIMIT {{limit}}",
              parameters: Jason.encode!(%{"limit" => 20})
            }
          }
        })
        |> get_in(["data", "updateDashboardPanel"])

      assert %{
               "id" => panel["id"],
               "dashboardId" => dashboard_id,
               "sql" => %{
                 "parameters" => %{"limit" => 20},
                 "query" => "SELECT * FROM intraday_metrics LIMIT {{limit}}"
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
        {:ok, mocked_clickhouse_result()}
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
                     "columns" => ["asset_id", "metric_id", "dt", "value", "computed_at"],
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
        {:ok, mocked_clickhouse_result()}
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
                 "columns" => ["asset_id", "metric_id", "dt", "value", "computed_at"],
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
                   "columns" => ["asset_id", "metric_id", "dt", "value", "computed_at"],
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

    test "compute panel and store it with a separate mutation", context do
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
        {:ok, mocked_clickhouse_result()}
      )
      |> Sanbase.Mock.run_with_mocks(fn ->
        result =
          execute_dashboard_panel_cache_mutation(
            context.conn,
            :compute_dashboard_panel,
            %{
              dashboard_id: dashboard["id"],
              panel_id: panel["id"]
            }
          )
          |> get_in(["data", "computeDashboardPanel"])

        stored =
          execute_dashboard_panel_cache_mutation(
            context.conn,
            :store_dashboard_panel,
            %{
              dashboard_id: dashboard["id"],
              panel_id: panel["id"],
              panel: %{
                map_as_input_object: true,
                san_query_id: result["sanQueryId"],
                clickhouse_query_id: result["clickhouseQueryId"],
                columns: result["columns"],
                rows: Jason.encode!(result["rows"]),
                summary: Jason.encode!(result["summary"]),
                query_start_time: result["queryStartTime"],
                query_end_time: result["queryEndTime"]
              }
            }
          )
          |> get_in(["data", "storeDashboardPanel"])

        dashboard_id = dashboard["id"]
        panel_id = panel["id"]
        san_query_id = result["sanQueryId"]
        query_start_time = result["queryStartTime"]
        query_end_time = result["queryEndTime"]

        assert %{
                 "clickhouseQueryId" => "177a5a3d-072b-48ac-8cf5-d8375c8314ef",
                 "columns" => ["asset_id", "metric_id", "dt", "value", "computed_at"],
                 "dashboardId" => ^dashboard_id,
                 "id" => ^panel_id,
                 "queryEndTime" => ^query_start_time,
                 "queryStartTime" => ^query_end_time,
                 "rows" => [
                   [2503, 250, "2008-12-10T00:00:00Z", 0.0, "2020-02-28T15:18:42Z"],
                   [2503, 250, "2008-12-10T00:05:00Z", 0.0, "2020-02-28T15:18:42Z"]
                 ],
                 "sanQueryId" => ^san_query_id,
                 "summary" => %{
                   "read_bytes" => "0",
                   "read_rows" => "0",
                   "total_rows_to_read" => "0",
                   "written_bytes" => "0",
                   "written_rows" => "0"
                 },
                 "updatedAt" => _
               } = stored

        dashboard_cache =
          get_dashboard_cache(context.conn, dashboard["id"])
          |> get_in(["data", "getDashboardCache"])

        dashboard_id = dashboard["id"]

        assert %{
                 "panels" => [
                   %{
                     "columns" => ["asset_id", "metric_id", "dt", "value", "computed_at"],
                     "dashboardId" => ^dashboard_id,
                     "id" => ^panel_id,
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
                     "updatedAt" => _
                   }
                 ]
               } = dashboard_cache
      end)
    end

    test "cannot store result bigger than the allowed limit", context do
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

      mock = mocked_clickhouse_result()

      # seed the rand generator so it gives the same result every time
      :rand.seed(:default, 42)

      rows =
        for i <- 1..25_000 do
          [
            0 + :rand.uniform(1000),
            0 + :rand.uniform(1000),
            "2008-#{rem(i, 12) + 1}-10T00:00:00Z",
            :rand.uniform() * 1000,
            "2020-#{rem(i, 12) + 1}-28T15:18:42Z"
          ]
        end

      mock = Map.put(mock, :rows, rows)

      Sanbase.Mock.prepare_mock2(
        &Sanbase.ClickhouseRepo.query/2,
        {:ok, mock}
      )
      |> Sanbase.Mock.run_with_mocks(fn ->
        error_msg =
          execute_dashboard_panel_cache_mutation(
            context.conn,
            :compute_and_store_dashboard_panel,
            %{
              dashboard_id: dashboard["id"],
              panel_id: panel["id"]
            }
          )
          |> get_in(["errors", Access.at(0), "message"])

        assert error_msg =~
                 "Cannot cache the panel because its compressed size is 517.88KB which is over the limit of 500KB"
      end)
    end
  end

  describe "execute raw queries" do
    test "compute raw clickhouse query", context do
      args = %{
        query:
          "SELECT * FROM intraday_metrics WHERE asset_id IN (SELECT asset_id FROM asset_metadata WHERE name = {{slug}}) LIMIT {{limit}}",
        parameters: %{slug: "bitcoin", limit: 2},
        map_as_input_object: true
      }

      mutation = """
      mutation{
        computeRawClickhouseQuery(#{map_to_args(args)}){
          columns
          rows
          clickhouseQueryId
          summary
        }
      }
      """

      Sanbase.Mock.prepare_mock2(
        &Sanbase.ClickhouseRepo.query/2,
        {:ok, mocked_clickhouse_result()}
      )
      |> Sanbase.Mock.run_with_mocks(fn ->
        result =
          context.conn
          |> post("/graphql", mutation_skeleton(mutation))
          |> json_response(200)
          |> get_in(["data", "computeRawClickhouseQuery"])

        assert result == %{
                 "clickhouseQueryId" => "177a5a3d-072b-48ac-8cf5-d8375c8314ef",
                 "columns" => ["asset_id", "metric_id", "dt", "value", "computed_at"],
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
                 }
               }
      end)
    end

    defp mocked_clickhouse_result() do
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
          parameters
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
        clickhouseQueryId
        sanQueryId
        dashboardId
        columns
        rows
        summary
        updatedAt
        queryStartTime
        queryEndTime
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
          columns
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
            "SELECT * FROM intraday_metrics WHERE asset_id IN (SELECT asset_id FROM asset_metadata WHERE name = {{slug}} LIMIT {{limit}})",
          parameters: Jason.encode!(%{"slug" => "bitcoin", "limit" => 20})
        }
      }
    }
  end
end
