defmodule SanbaseWeb.Graphql.DashboardsApiTest do
  use SanbaseWeb.ConnCase, async: false

  import Mock
  import Sanbase.Factory
  import Sanbase.QueriesMocks
  import SanbaseWeb.Graphql.TestHelpers
  import SanbaseWeb.QueriesApiHelpers
  import SanbaseWeb.DashboardsApiHelpers

  setup do
    user = insert(:user)
    user2 = insert(:user)
    conn = setup_jwt_auth(build_conn(), user)
    conn2 = setup_jwt_auth(build_conn(), user2)

    %{conn: conn, conn2: conn2, user: user, user2: user2}
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

      mapping =
        execute_dashboard_query_mutation(context.conn, :update_dashboard_query, %{
          dashboard_id: dashboard.id,
          dashboard_query_mapping_id: mapping["id"],
          settings: %{layout: [1, 2, 1, 0]}
        })
        |> get_in(["data", "updateDashboardQuery"])

      # The user is properly preloaded
      assert is_binary(mapping["query"]["user"]["id"])
      assert is_binary(mapping["dashboard"]["user"]["id"])

      assert %{"id" => ^dashboard_id} = mapping["dashboard"]
      assert %{"id" => ^query_id} = mapping["query"]
      assert %{"settings" => %{"layout" => [1, 2, 1, 0]}} = mapping
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

      # The user is properly preloaded
      assert is_binary(mapping["query"]["user"]["id"])
      assert is_binary(mapping["dashboard"]["user"]["id"])

      # Assert that the dashboard has exactly 1 query added
      assert {:ok, %{queries: [_]}} =
               Sanbase.Dashboards.get_dashboard(dashboard.id, context.user.id)

      result =
        execute_dashboard_query_mutation(context.conn, :delete_dashboard_query, %{
          dashboard_id: dashboard.id,
          dashboard_query_mapping_id: mapping["id"]
        })
        |> get_in(["data", "deleteDashboardQuery"])

      # The user is properly preloaded
      assert is_binary(result["query"]["user"]["id"])
      assert is_binary(result["dashboard"]["user"]["id"])

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

  describe "Run Dashboard Queries" do
    test "run dashboard query (override params via the run query)", context do
      # In test env the storing runs not async and there's a 7500ms sleep
      Application.put_env(:__sanbase_queries__, :__store_execution_details__, false)

      on_exit(fn ->
        Application.delete_env(:__sanbase_queries__, :__store_execution_details__)
      end)

      {:ok, query} = create_query(context.user.id)

      {:ok, dashboard} =
        Sanbase.Dashboards.create_dashboard(%{name: "My Dashboard"}, context.user.id)

      {:ok, mapping} = create_dashboard_query(context.conn, dashboard, query)

      # Add global parameters and override the query's local parameters
      dashboard_key = "slug"
      query_key = "slug"
      param_value = "santiment"

      {:ok, _dashboard_with_params} =
        add_dashboard_global_parameter(
          context.conn,
          dashboard,
          dashboard_key,
          :string,
          param_value
        )

      # Add global parameter override for a query local parameter
      param_override_args = %{
        dashboard_id: dashboard.id,
        dashboard_query_mapping_id: mapping["id"],
        dashboard_parameter_key: dashboard_key,
        query_parameter_key: query_key
      }

      {:ok, _} =
        add_dashboard_global_parameter_override(
          context.conn,
          param_override_args,
          param_value
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
            dashboard_query_mapping_id: mapping["id"],
            # store_execution: true,
            parameters_override: %{slug: "new_value_from_query_bitcoin"}
          })

        assert "errors" not in Map.keys(result)
        assert is_map(get_in(result, ["data", "runDashboardSqlQuery"]))

        # Check that the used argument is the one provided in the API
        assert_called(Sanbase.ClickhouseRepo.query(:_, ["new_value_from_query_bitcoin", 10]))
      end)
    end

    test "run and store dashboard query, even if not owner", context do
      # In test env the storing runs not async and there's a 7500ms sleep
      Application.put_env(:__sanbase_queries__, :__store_execution_details__, false)

      on_exit(fn ->
        Application.delete_env(:__sanbase_queries__, :__store_execution_details__)
      end)

      {:ok, query} = create_query(context.user.id)

      {:ok, dashboard} =
        Sanbase.Dashboards.create_dashboard(%{name: "My Dashboard"}, context.user.id)

      {:ok, mapping} = create_dashboard_query(context.conn, dashboard, query)

      # Add global parameters and override the query's local parameters
      dashboard_key = "slug"
      query_key = "slug"
      param_value = "santiment"

      {:ok, _dashboard_with_params} =
        add_dashboard_global_parameter(
          context.conn,
          dashboard,
          dashboard_key,
          :string,
          param_value
        )

      # Add global parameter override for a query local parameter
      param_override_args = %{
        dashboard_id: dashboard.id,
        dashboard_query_mapping_id: mapping["id"],
        dashboard_parameter_key: dashboard_key,
        query_parameter_key: query_key
      }

      {:ok, _} =
        add_dashboard_global_parameter_override(
          context.conn,
          param_override_args,
          param_value
        )

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
                   ["bitcoin", 250, "2008-12-10T00:00:00Z", +0.0, "2020-02-28T15:18:42Z"],
                   ["bitcoin", 250, "2008-12-10T00:05:00Z", +0.0, "2020-02-28T15:18:42Z"]
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

    test "run dashboard query (resolve global parameters)", context do
      # In test env the storing runs not async and there's a 7500ms sleep
      Application.put_env(:__sanbase_queries__, :__store_execution_details__, false)

      on_exit(fn ->
        Application.delete_env(:__sanbase_queries__, :__store_execution_details__)
      end)

      {:ok, query} = create_query(context.user.id)

      {:ok, dashboard} =
        Sanbase.Dashboards.create_dashboard(%{name: "My Dashboard"}, context.user.id)

      {:ok, mapping} = create_dashboard_query(context.conn, dashboard, query)

      # Add global parameters and override the query's local parameters
      dashboard_key = "slug"
      query_key = "slug"
      param_value = "santiment"

      {:ok, _dashboard_with_params} =
        add_dashboard_global_parameter(
          context.conn,
          dashboard,
          dashboard_key,
          :string,
          param_value
        )

      # Add global parameter override for a query local parameter
      param_override_args = %{
        dashboard_id: dashboard.id,
        dashboard_query_mapping_id: mapping["id"],
        dashboard_parameter_key: dashboard_key,
        query_parameter_key: query_key
      }

      {:ok, _} =
        add_dashboard_global_parameter_override(
          context.conn,
          param_override_args,
          param_value
        )

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
                   ["bitcoin", 250, "2008-12-10T00:00:00Z", +0.0, "2020-02-28T15:18:42Z"],
                   ["bitcoin", 250, "2008-12-10T00:05:00Z", +0.0, "2020-02-28T15:18:42Z"]
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

    defp create_dashboard_query(conn, dashboard, query) do
      query_id = query.id
      dashboard_id = dashboard.id

      # Add a query to a dashboard
      mapping =
        execute_dashboard_query_mutation(conn, :create_dashboard_query, %{
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

      {:ok, mapping}
    end

    defp add_dashboard_global_parameter(conn, dashboard, key, type, value) do
      dashboard_with_params =
        execute_global_parameter_mutation(
          conn,
          :add_dashboard_global_parameter,
          %{
            dashboard_id: dashboard.id,
            key: key,
            value: %{type => value, map_as_input_object: true}
          }
        )
        |> get_in(["data", "addDashboardGlobalParameter"])

      %{"parameters" => parameters} = dashboard_with_params
      assert parameters[key] == %{"overrides" => [], "value" => value}

      {:ok, dashboard_with_params}
    end

    defp add_dashboard_global_parameter_override(
           conn,
           param_override_args,
           parameter_value
         ) do
      override =
        execute_global_parameter_mutation(
          conn,
          :add_dashboard_global_parameter_override,
          param_override_args
        )
        |> get_in(["data", "addDashboardGlobalParameterOverride"])

      assert override == %{
               "parameters" => %{
                 param_override_args[:dashboard_parameter_key] => %{
                   "overrides" => [
                     %{
                       "dashboard_query_mapping_id" =>
                         param_override_args[:dashboard_query_mapping_id],
                       "parameter" => param_override_args[:query_parameter_key]
                     }
                   ],
                   "value" => parameter_value
                 }
               }
             }

      {:ok, override}
    end
  end

  describe "Caching" do
    test "cache queries on a dashboard", context do
      # In test env the storing runs not async and there's a 7500ms sleep
      Application.put_env(:__sanbase_queries__, :__store_execution_details__, false)

      on_exit(fn ->
        Application.delete_env(:__sanbase_queries__, :__store_execution_details__)
      end)

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
                       ["bitcoin", 250, "2008-12-10T00:00:00Z", +0.0, "2020-02-28T15:18:42Z"],
                       ["bitcoin", 250, "2008-12-10T00:05:00Z", +0.0, "2020-02-28T15:18:42Z"]
                     ]
                   }
                 ]
               } = stored

        assert datetime_close_to_now?(Sanbase.DateTimeUtils.from_iso8601!(query_start_time))
        assert datetime_close_to_now?(Sanbase.DateTimeUtils.from_iso8601!(query_end_time))

        cache =
          get_cached_dashboard_queries_executions(context.conn, %{dashboard_id: dashboard.id})
          |> get_in(["data", "getCachedDashboardQueriesExecutions", "queries"])

        assert [
                 %{
                   "queryId" => ^query_id,
                   "dashboardQueryMappingId" => ^dashboard_query_mapping_id,
                   "clickhouseQueryId" => "177a5a3d-072b-48ac-8cf5-d8375c8314ef",
                   "columnTypes" => ["UInt64", "UInt64", "DateTime", "Float64", "DateTime"],
                   "columns" => ["asset_id", "metric_id", "dt", "value", "computed_at"],
                   "queryStartTime" => query_start_time,
                   "queryEndTime" => query_end_time,
                   "rows" => [
                     ["bitcoin", 250, "2008-12-10T00:00:00Z", +0.0, "2020-02-28T15:18:42Z"],
                     ["bitcoin", 250, "2008-12-10T00:05:00Z", +0.0, "2020-02-28T15:18:42Z"]
                   ]
                 }
               ] = cache

        assert datetime_close_to_now?(Sanbase.DateTimeUtils.from_iso8601!(query_start_time))
        assert datetime_close_to_now?(Sanbase.DateTimeUtils.from_iso8601!(query_end_time))
      end)
    end

    test "other users can store dashboards cache", context do
      # In test env the storing runs not async and there's a 7500ms sleep
      Application.put_env(:__sanbase_queries__, :__store_execution_details__, false)

      on_exit(fn ->
        Application.delete_env(:__sanbase_queries__, :__store_execution_details__)
      end)

      {:ok, query} = create_query(context.user.id)

      {:ok, dashboard} =
        Sanbase.Dashboards.create_dashboard(%{name: "Dash", is_public: true}, context.user.id)

      {:ok, dashboard2} =
        Sanbase.Dashboards.create_dashboard(%{name: "Dash", is_public: false}, context.user.id)

      {:ok, mapping} = create_dashboard_query(context.conn, dashboard, query)
      {:ok, mapping2} = create_dashboard_query(context.conn, dashboard2, query)

      mock_fun =
        Sanbase.Mock.wrap_consecutives(
          [
            fn -> {:ok, mocked_clickhouse_result()} end,
            fn -> {:ok, mocked_execution_details_result()} end
          ],
          arity: 2
        )

      Sanbase.Mock.prepare_mock(Sanbase.ClickhouseRepo, :query, mock_fun)
      |> Sanbase.Mock.run_with_mocks(fn ->
        # Users can run and cache other users public dashboards
        result =
          run_sql_query(context.conn2, :run_dashboard_sql_query, %{
            dashboard_id: dashboard.id,
            dashboard_query_mapping_id: mapping["id"],
            store_execution: true
          })

        assert "errors" not in Map.keys(result)

        assert %{} = get_in(result, ["data", "runDashboardSqlQuery"])

        cache =
          get_cached_dashboard_queries_executions(context.conn, %{
            dashboard_id: dashboard.id
          })
          |> get_in(["data", "getCachedDashboardQueriesExecutions"])

        # A cache record has been created
        assert %{"queries" => [_]} = cache

        # Users cannot run and cache other users private dashboards
        result =
          run_sql_query(context.conn2, :run_dashboard_sql_query, %{
            dashboard_id: dashboard2.id,
            dashboard_query_mapping_id: mapping2["id"],
            store_execution: true
          })

        assert "errors" in Map.keys(result)

        assert get_in(result, ["errors", Access.at(0), "message"]) =~
                 "does not exist, it is not part of dashboard #{dashboard2.id}, or the dashboard is not public"

        error_msg =
          get_cached_dashboard_queries_executions(context.conn2, %{
            dashboard_id: dashboard2.id
          })
          |> get_in(["errors", Access.at(0), "message"])

        assert error_msg =~
                 "does not exist or the dashboard is private and the user with id #{context.user2.id} is not the owner of it."

        # Users can run and cache their own private dashboards
        result2 =
          run_sql_query(context.conn, :run_dashboard_sql_query, %{
            dashboard_id: dashboard2.id,
            dashboard_query_mapping_id: mapping2["id"],
            store_execution: true
          })

        assert "errors" not in Map.keys(result2)

        assert %{} = get_in(result2, ["data", "runDashboardSqlQuery"])

        cache2 =
          get_cached_dashboard_queries_executions(context.conn, %{
            dashboard_id: dashboard2.id
          })
          |> get_in(["data", "getCachedDashboardQueriesExecutions"])

        # A cache record has been created
        assert %{"queries" => [_]} = cache2
      end)
    end

    test "run dashboard query with storeExecution: true", context do
      # In test env the storing runs not async and there's a 7500ms sleep
      Application.put_env(:__sanbase_queries__, :__store_execution_details__, false)

      on_exit(fn ->
        Application.delete_env(:__sanbase_queries__, :__store_execution_details__)
      end)

      {:ok, query} = create_query(context.user.id)
      {:ok, dashboard} = Sanbase.Dashboards.create_dashboard(%{name: "Dash"}, context.user.id)
      {:ok, mapping} = create_dashboard_query(context.conn, dashboard, query)

      # Add global parameters and override the query's local parameters
      dashboard_key = "slug"
      query_key = "slug"
      param_value = "santiment"

      {:ok, _dashboard_with_params} =
        add_dashboard_global_parameter(
          context.conn,
          dashboard,
          dashboard_key,
          :string,
          param_value
        )

      # Add global parameter override for a query local parameter
      param_override_args = %{
        dashboard_id: dashboard.id,
        dashboard_query_mapping_id: mapping["id"],
        dashboard_parameter_key: dashboard_key,
        query_parameter_key: query_key
      }

      {:ok, _} =
        add_dashboard_global_parameter_override(
          context.conn,
          param_override_args,
          param_value
        )

      mock_fun =
        Sanbase.Mock.wrap_consecutives(
          [
            fn -> {:ok, mocked_clickhouse_result("bitcoin")} end,
            fn -> {:ok, mocked_clickhouse_result("santiment")} end,
            fn -> {:ok, mocked_execution_details_result()} end,
            fn -> {:ok, mocked_execution_details_result()} end
          ],
          arity: 2
        )

      # Run a dashboard query. Expect the dashboard parameter to override
      # the query local parameter
      Sanbase.Mock.prepare_mock(Sanbase.ClickhouseRepo, :query, mock_fun)
      |> Sanbase.Mock.run_with_mocks(fn ->
        # Check that the used argument is the one provided in the API
        parameters_override = %{slug: "bitcoin"}

        result1 =
          run_sql_query(context.conn, :run_dashboard_sql_query, %{
            dashboard_id: dashboard.id,
            dashboard_query_mapping_id: mapping["id"],
            store_execution: true,
            parameters_override: parameters_override
          })

        # Only one cache record
        assert [_] = Sanbase.Repo.all(Sanbase.Dashboards.DashboardCache)

        assert "errors" not in Map.keys(result1)
        assert is_map(get_in(result1, ["data", "runDashboardSqlQuery"]))

        assert_called(Sanbase.ClickhouseRepo.query(:_, ["bitcoin", 10]))
        refute called(Sanbase.ClickhouseRepo.query(:_, ["santiment", 10]))

        result2 =
          run_sql_query(context.conn, :run_dashboard_sql_query, %{
            dashboard_id: dashboard.id,
            dashboard_query_mapping_id: mapping["id"],
            store_execution: true
          })

        # Now a second cache record appears.
        assert [_, _] = Sanbase.Repo.all(Sanbase.Dashboards.DashboardCache)

        # No parameters_override, so the original param is used
        assert_called(Sanbase.ClickhouseRepo.query(:_, ["santiment", 10]))

        assert "errors" not in Map.keys(result2)
        assert is_map(get_in(result2, ["data", "runDashboardSqlQuery"]))

        cache1 =
          get_cached_dashboard_queries_executions(context.conn, %{
            dashboard_id: dashboard.id,
            parameters_override: parameters_override
          })
          |> get_in(["data", "getCachedDashboardQueriesExecutions", "queries"])

        assert [
                 %{
                   "clickhouseQueryId" => _,
                   "columnTypes" => ["UInt64", "UInt64", "DateTime", "Float64", "DateTime"],
                   "columns" => ["asset_id", "metric_id", "dt", "value", "computed_at"],
                   "dashboardQueryMappingId" => _mapping_id,
                   "queryEndTime" => _end_time,
                   "queryId" => _query_id,
                   "queryStartTime" => _start_time,
                   "rows" => [
                     ["bitcoin", 250, "2008-12-10T00:00:00Z", +0.0, "2020-02-28T15:18:42Z"],
                     ["bitcoin", 250, "2008-12-10T00:05:00Z", +0.0, "2020-02-28T15:18:42Z"]
                   ]
                 }
               ] =
                 cache1

        # Fetched without the parameters override
        cache2 =
          get_cached_dashboard_queries_executions(context.conn, %{
            dashboard_id: dashboard.id
          })
          |> get_in(["data", "getCachedDashboardQueriesExecutions", "queries"])

        assert [
                 %{
                   "clickhouseQueryId" => _,
                   "columnTypes" => ["UInt64", "UInt64", "DateTime", "Float64", "DateTime"],
                   "columns" => ["asset_id", "metric_id", "dt", "value", "computed_at"],
                   "dashboardQueryMappingId" => _mapping_id,
                   "queryEndTime" => _end_time,
                   "queryId" => _query_id,
                   "queryStartTime" => _start_time,
                   "rows" => [
                     ["santiment", 250, "2008-12-10T00:00:00Z", +0.0, "2020-02-28T15:18:42Z"],
                     ["santiment", 250, "2008-12-10T00:05:00Z", +0.0, "2020-02-28T15:18:42Z"]
                   ]
                 }
               ] =
                 cache2
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
