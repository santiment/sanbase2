defmodule SanbaseWeb.Graphql.DashboardsApiTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import Sanbase.QueriesMocks
  import SanbaseWeb.Graphql.TestHelpers
  import SanbaseWeb.QueriesApiHelpers
  import SanbaseWeb.DashboardsApiHelpers

  setup do
    user = insert(:user)
    conn = setup_jwt_auth(build_conn(), user)

    %{conn: conn, user: user}
  end

  describe "voting" do
    test "dashboards ", context do
      dashboard_id =
        execute_dashboard_mutation(context.conn, :create_dashboard)
        |> get_in(["data", "createDashboard", "id"])

      vote = fn ->
        vote_result =
          context.conn
          |> post(
            "/graphql",
            mutation_skeleton(
              "mutation{ vote(dashboardId: #{dashboard_id}) { votedAt votes { totalVotes } } }"
            )
          )
          |> json_response(200)
          |> get_in(["data", "vote"])

        vote_result
      end

      for i <- 1..10 do
        vote = vote.()
        assert %{"votedAt" => _, "votes" => %{"totalVotes" => ^i}} = vote
      end

      total_votes =
        get_dashboard(context.conn, dashboard_id)
        |> get_in(["data", "getDashboard", "votes", "totalVotes"])

      assert total_votes == 10
    end
  end

  describe "CRUD Dashboards APIs" do
    test "create dashboard", context do
      result =
        execute_dashboard_mutation(context.conn, :create_dashboard, %{
          name: "MyDashboard",
          description: "some text",
          is_public: true,
          settings: %{"some_var" => [0, 1, 2, 3]}
        })
        |> get_in(["data", "createDashboard"])

      user_id = context.user.id |> to_string()

      assert %{
               "name" => "MyDashboard",
               "description" => "some text",
               "queries" => [],
               "user" => %{"id" => ^user_id}
             } = result
    end

    test "get dashboard", context do
      dashboard_id =
        execute_dashboard_mutation(context.conn, :create_dashboard)
        |> get_in(["data", "createDashboard", "id"])

      dashboard =
        get_dashboard(context.conn, dashboard_id)
        |> get_in(["data", "getDashboard"])

      assert %{
               "description" => "some text",
               "id" => _,
               "isPublic" => true,
               "name" => "MyDashboard",
               "queries" => [],
               "settings" => %{"some_key" => [0, 1, 2, 3]},
               "votes" => %{"totalVotes" => 0}
             } = dashboard
    end

    test "update dashboard", context do
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
               "queries" => [],
               "user" => %{"id" => ^user_id}
             } = result
    end

    test "delete dashboard", context do
      dashboard_id =
        execute_dashboard_mutation(context.conn, :create_dashboard)
        |> get_in(["data", "createDashboard", "id"])

      execute_dashboard_mutation(context.conn, :delete_dashboard, %{id: dashboard_id})

      assert {:error, error_msg} = Sanbase.Dashboards.get_dashboard(dashboard_id, context.user.id)
      assert error_msg =~ "does not exist"
    end

    test "add dashboard global parameters", context do
      {:ok, dashboard} =
        Sanbase.Dashboards.create_dashboard(%{name: "My Dashboard"}, context.user.id)

      # Add global parameters and override the query's local parameters
      dashboard_with_params =
        execute_global_parameter_mutation(
          context.conn,
          :add_dashboard_global_parameter,
          %{
            dashboard_id: dashboard.id,
            key: "slug",
            value: %{string: "santiment", map_as_input_object: true}
          }
        )
        |> get_in(["data", "addDashboardGlobalParameter"])

      assert dashboard_with_params == %{
               "parameters" => %{"slug" => %{"overrides" => [], "value" => "santiment"}}
             }

      # Add another param
      dashboard_with_params =
        execute_global_parameter_mutation(
          context.conn,
          :add_dashboard_global_parameter,
          %{
            dashboard_id: dashboard.id,
            key: "limit",
            value: %{integer: 20, map_as_input_object: true}
          }
        )
        |> get_in(["data", "addDashboardGlobalParameter"])

      assert dashboard_with_params == %{
               "parameters" => %{
                 "slug" => %{"overrides" => [], "value" => "santiment"},
                 "limit" => %{"overrides" => [], "value" => 20}
               }
             }

      # Update parameter
      dashboard_with_params =
        execute_global_parameter_mutation(
          context.conn,
          :update_dashboard_global_parameter,
          %{
            dashboard_id: dashboard.id,
            key: "slug",
            new_key: "slug2",
            new_value: %{string: "bitcoin", map_as_input_object: true}
          }
        )
        |> get_in(["data", "updateDashboardGlobalParameter"])

      assert dashboard_with_params == %{
               "parameters" => %{
                 "slug2" => %{"overrides" => [], "value" => "bitcoin"},
                 "limit" => %{"overrides" => [], "value" => 20}
               }
             }
    end
  end

  describe "Dashboard Queries CRUD" do
    test "add a query to a dashboard", context do
      {:ok, dashboard} =
        Sanbase.Dashboards.create_dashboard(%{name: "My Dashboard"}, context.user.id)

      {:ok, %{id: query_id} = query} = create_query(context.user.id)

      _mapping =
        execute_dashboard_query_mutation(context.conn, :create_dashboard_query, %{
          dashboard_id: dashboard.id,
          query_id: query.id
        })
        |> get_in(["data", "createDashboardQuery"])

      dashboard =
        get_dashboard(context.conn, dashboard.id)
        |> get_in(["data", "getDashboard"])

      assert [%{"id" => ^query_id}] = dashboard["queries"]
    end

    test "update a dashboard query", context do
      {:ok, %{id: dashboard_id} = dashboard} =
        Sanbase.Dashboards.create_dashboard(%{name: "My Dashboard"}, context.user.id)

      {:ok, %{id: query_id} = query} = create_query(context.user.id)

      mapping =
        execute_dashboard_query_mutation(context.conn, :create_dashboard_query, %{
          dashboard_id: dashboard.id,
          query_id: query.id
        })
        |> get_in(["data", "createDashboardQuery"])

      dashboard_query_mapping =
        execute_dashboard_query_mutation(context.conn, :update_dashboard_query, %{
          dashboard_id: dashboard.id,
          dashboard_query_mapping_id: mapping["id"],
          settings: %{layout: [1, 2, 1, 0]}
        })
        |> get_in(["data", "updateDashboardQuery"])

      assert %{"id" => ^dashboard_id} = dashboard_query_mapping["dashboard"]
      assert %{"id" => ^query_id} = dashboard_query_mapping["query"]
      assert %{"settings" => %{"layout" => [1, 2, 1, 0]}} = dashboard_query_mapping
    end

    test "delete dashboard query", context do
      {:ok, query} = create_query(context.user.id)

      {:ok, dashboard} =
        Sanbase.Dashboards.create_dashboard(%{name: "My Dashboard"}, context.user.id)

      # Add a query to a dashboard
      mapping =
        execute_dashboard_query_mutation(context.conn, :create_dashboard_query, %{
          dashboard_id: dashboard.id,
          query_id: query.id,
          settings: %{layout: [0, 1, 2, 3, 4]}
        })
        |> get_in(["data", "createDashboardQuery"])

      # Assert that the dashboard has exactly 1 query added
      assert {:ok, %{queries: [_]}} =
               Sanbase.Dashboards.get_dashboard(dashboard.id, context.user.id)

      result =
        execute_dashboard_query_mutation(context.conn, :delete_dashboard_query, %{
          dashboard_id: dashboard.id,
          dashboard_query_mapping_id: mapping["id"]
        })
        |> get_in(["data", "deleteDashboardQuery"])

      dashboard_query_mapping_id = mapping["id"]

      query_id = query.id
      dashboard_id = dashboard.id

      assert %{
               "dashboard" => %{"id" => ^dashboard_id, "parameters" => %{}},
               "id" => ^dashboard_query_mapping_id,
               "query" => %{
                 "id" => ^query_id,
                 "sqlQueryParameters" => %{"limit" => 10, "slug" => "bitcoin"},
                 "sqlQueryText" =>
                   "SELECT * FROM intraday_metrics WHERE asset_id = get_asset_id({{slug}}) LIMIT {{limit}}"
               },
               "settings" => %{"layout" => [0, 1, 2, 3, 4]}
             } = result

      # Assert that the dashboard has no queries

      assert {:ok, %{queries: []}} =
               Sanbase.Dashboards.get_dashboard(dashboard_id, context.user.id)
    end
  end

  describe "Run Dashboar Queries" do
    test "run dashboard query (resolve global params)", context do
      # In test env the storing runs not async and there's a 7500ms sleep
      Application.put_env(:__sanbase_queries__, :__store_execution_details__, false)

      on_exit(fn -> Application.delete_env(:__sanbase_queries__, :__store_execution_details__) end)

      {:ok, query} = create_query(context.user.id)

      {:ok, dashboard} =
        Sanbase.Dashboards.create_dashboard(%{name: "My Dashboard"}, context.user.id)

      query_id = query.id
      dashboard_id = dashboard.id

      # Add a query to a dashboard
      mapping =
        execute_dashboard_query_mutation(context.conn, :create_dashboard_query, %{
          dashboard_id: dashboard.id,
          query_id: query.id,
          settings: %{layout: [0, 1, 2, 3, 4]}
        })
        |> get_in(["data", "createDashboardQuery"])

      assert %{
               "dashboard" => %{"id" => ^dashboard_id, "parameters" => %{}},
               "id" => _,
               "query" => %{"id" => ^query_id},
               "settings" => %{"layout" => [0, 1, 2, 3, 4]}
             } = mapping

      # Add global parameters and override the query's local parameters
      dashboard_with_params =
        execute_global_parameter_mutation(
          context.conn,
          :add_dashboard_global_parameter,
          %{
            dashboard_id: dashboard.id,
            key: "slug",
            value: %{string: "santiment", map_as_input_object: true}
          }
        )
        |> get_in(["data", "addDashboardGlobalParameter"])

      assert dashboard_with_params == %{
               "parameters" => %{"slug" => %{"overrides" => [], "value" => "santiment"}}
             }

      # Add global parameter override for a query local parameter
      param_override_args = %{
        dashboard_id: dashboard.id,
        dashboard_query_mapping_id: mapping["id"],
        dashboard_parameter_key: "slug",
        query_parameter_key: "slug"
      }

      override =
        execute_global_parameter_mutation(
          context.conn,
          :add_dashboard_global_parameter_override,
          param_override_args
        )
        |> get_in(["data", "addDashboardGlobalParameterOverride"])

      assert override == %{
               "parameters" => %{
                 "slug" => %{
                   "overrides" => [
                     %{"dashboard_query_mapping_id" => mapping["id"], "parameter" => "slug"}
                   ],
                   "value" => "santiment"
                 }
               }
             }

      # Delete global parameter override for a query local parameter
      override =
        execute_global_parameter_mutation(
          context.conn,
          :delete_dashboard_global_parameter_override,
          param_override_args |> Map.delete(:query_parameter_key)
        )
        |> get_in(["data", "deleteDashboardGlobalParameterOverride"])

      assert override == %{
               "parameters" => %{
                 "slug" => %{"overrides" => [], "value" => "santiment"}
               }
             }

      # Add back the deleted param override
      execute_global_parameter_mutation(
        context.conn,
        :add_dashboard_global_parameter_override,
        param_override_args
      )

      mock_fun =
        Sanbase.Mock.wrap_consecutives(
          [
            fn -> {:ok, mocked_clickhouse_result()} end,
            fn -> {:ok, mocked_execution_details_result()} end
          ],
          arity: 2
        )

      # Run a dashboard query. Expect the dashboard parameter to override
      # the query local parameter
      Sanbase.Mock.prepare_mock(Sanbase.ClickhouseRepo, :query, mock_fun)
      |> Sanbase.Mock.run_with_mocks(fn ->
        result =
          run_sql_query(context.conn, :run_dashboard_sql_query, %{
            dashboard_id: dashboard.id,
            dashboard_query_mapping_id: mapping["id"]
          })
          |> get_in(["data", "runDashboardSqlQuery"])

        assert %{
                 "clickhouseQueryId" => "177a5a3d-072b-48ac-8cf5-d8375c8314ef",
                 "columns" => ["asset_id", "metric_id", "dt", "value", "computed_at"],
                 "columnTypes" => ["UInt64", "UInt64", "DateTime", "Float64", "DateTime"],
                 "rows" => [
                   [2503, 250, "2008-12-10T00:00:00Z", +0.0, "2020-02-28T15:18:42Z"],
                   [2503, 250, "2008-12-10T00:05:00Z", +0.0, "2020-02-28T15:18:42Z"]
                 ],
                 "summary" => %{
                   "read_bytes" => +0.0,
                   "read_rows" => +0.0,
                   "total_rows_to_read" => +0.0,
                   "written_bytes" => +0.0,
                   "written_rows" => +0.0
                 }
               } = result
      end)
    end
  end

  describe "Caching" do
    test "cache queries on a dashboard", context do
      # In test env the storing runs not async and there's a 7500ms sleep
      Application.put_env(:__sanbase_queries__, :__store_execution_details__, false)

      on_exit(fn -> Application.delete_env(:__sanbase_queries__, :__store_execution_details__) end)

      {:ok, query} = Sanbase.Queries.create_query(%{name: "Query"}, context.user.id)

      {:ok, dashboard} =
        Sanbase.Dashboards.create_dashboard(%{name: "Dashboard"}, context.user.id)

      {:ok, dashboard_query_mapping} =
        Sanbase.Dashboards.add_query_to_dashboard(
          dashboard.id,
          query.id,
          context.user.id
        )

      mock_fun =
        Sanbase.Mock.wrap_consecutives(
          [
            fn -> {:ok, mocked_clickhouse_result()} end,
            fn -> {:ok, mocked_execution_details_result()} end
          ],
          arity: 2
        )

      # Run a dashboard query. Expect the dashboard parameter to override
      # the query local parameter
      Sanbase.Mock.prepare_mock(Sanbase.ClickhouseRepo, :query, mock_fun)
      |> Sanbase.Mock.run_with_mocks(fn ->
        dashboard_query_mapping_id = dashboard_query_mapping.id
        query_id = query.id

        result =
          run_sql_query(context.conn, :run_dashboard_sql_query, %{
            dashboard_id: dashboard.id,
            dashboard_query_mapping_id: dashboard_query_mapping.id
          })
          |> get_in(["data", "runDashboardSqlQuery"])

        compressed_result = Jason.encode!(result) |> :zlib.gzip() |> Base.encode64()

        stored =
          cache_dashboard_query_execution(context.conn, %{
            dashboard_id: dashboard.id,
            dashboard_query_mapping_id: dashboard_query_mapping.id,
            compressed_query_execution_result: compressed_result
          })
          |> get_in(["data", "storeDashboardQueryExecution"])

        assert %{
                 "queries" => [
                   %{
                     "clickhouseQueryId" => "177a5a3d-072b-48ac-8cf5-d8375c8314ef",
                     "columnTypes" => ["UInt64", "UInt64", "DateTime", "Float64", "DateTime"],
                     "columns" => ["asset_id", "metric_id", "dt", "value", "computed_at"],
                     "dashboardQueryMappingId" => ^dashboard_query_mapping_id,
                     "queryStartTime" => query_start_time,
                     "queryEndTime" => query_end_time,
                     "queryId" => ^query_id,
                     "rows" => [
                       [2503, 250, "2008-12-10T00:00:00Z", +0.0, "2020-02-28T15:18:42Z"],
                       [2503, 250, "2008-12-10T00:05:00Z", +0.0, "2020-02-28T15:18:42Z"]
                     ]
                   }
                 ]
               } = stored

        assert datetime_close_to_now?(Sanbase.DateTimeUtils.from_iso8601!(query_start_time))
        assert datetime_close_to_now?(Sanbase.DateTimeUtils.from_iso8601!(query_end_time))

        cache =
          get_cached_dashboard_queries_executions(context.conn, %{dashboard_id: dashboard.id})
          |> get_in(["data", "getCachedDashboardQueriesExecutions"])

        assert %{
                 "queries" => [
                   %{
                     "queryId" => ^query_id,
                     "dashboardQueryMappingId" => ^dashboard_query_mapping_id,
                     "clickhouseQueryId" => "177a5a3d-072b-48ac-8cf5-d8375c8314ef",
                     "columnTypes" => ["UInt64", "UInt64", "DateTime", "Float64", "DateTime"],
                     "columns" => ["asset_id", "metric_id", "dt", "value", "computed_at"],
                     "queryStartTime" => query_start_time,
                     "queryEndTime" => query_end_time,
                     "rows" => [
                       [2503, 250, "2008-12-10T00:00:00Z", +0.0, "2020-02-28T15:18:42Z"],
                       [2503, 250, "2008-12-10T00:05:00Z", +0.0, "2020-02-28T15:18:42Z"]
                     ]
                   }
                 ]
               } = cache

        assert datetime_close_to_now?(Sanbase.DateTimeUtils.from_iso8601!(query_start_time))
        assert datetime_close_to_now?(Sanbase.DateTimeUtils.from_iso8601!(query_end_time))
      end)
    end

    defp datetime_close_to_now?(dt) do
      Sanbase.TestUtils.datetime_close_to(
        Timex.now(),
        dt,
        2,
        :seconds
      )
    end
  end

  defp create_query(user_id) do
    Sanbase.Queries.create_query(
      %{
        sql_query_text:
          "SELECT * FROM intraday_metrics WHERE asset_id = get_asset_id({{slug}}) LIMIT {{limit}}",
        sql_query_parameters: %{slug: "bitcoin", limit: 10}
      },
      user_id
    )
  end
end
