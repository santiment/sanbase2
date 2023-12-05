defmodule SanbaseWeb.Graphql.QueriesApiTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

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

    test "queries ", context do
      query_id =
        execute_sql_query_mutation(context.conn, :create_sql_query)
        |> get_in(["data", "createSqlQuery", "id"])

      vote = fn ->
        vote_result =
          context.conn
          |> post(
            "/graphql",
            mutation_skeleton(
              "mutation{ vote(queryId: #{query_id}) { votedAt votes { totalVotes } } }"
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
        get_sql_query(context.conn, query_id)
        |> get_in(["data", "getSqlQuery", "votes", "totalVotes"])

      assert total_votes == 10
    end
  end

  describe "CRUD Queries APIs" do
    test "create", context do
      sql_query =
        execute_sql_query_mutation(context.conn, :create_sql_query, %{
          name: "My Query",
          description: "some desc",
          is_public: true,
          sql_query_text:
            "SELECT * FROM intraday_metrics WHERE asset_id = get_asset_id({{slug}})",
          sql_query_parameters: %{slug: "bitcoin"},
          settings: %{"some_var" => [0, 1, 2, 3]}
        })
        |> get_in(["data", "createSqlQuery"])

      user_id = context.user.id |> to_string()

      assert assert %{
                      "description" => "some desc",
                      "name" => "My Query",
                      "user" => %{"id" => ^user_id},
                      "id" => _,
                      "settings" => %{"some_var" => [0, 1, 2, 3]},
                      "sqlQueryParameters" => %{"slug" => "bitcoin"},
                      "sqlQueryText" =>
                        "SELECT * FROM intraday_metrics WHERE asset_id = get_asset_id({{slug}})"
                    } = sql_query
    end

    test "get", context do
      sql_query_id =
        execute_sql_query_mutation(context.conn, :create_sql_query)
        |> get_in(["data", "createSqlQuery", "id"])

      sql_query =
        get_sql_query(context.conn, sql_query_id)
        |> get_in(["data", "getSqlQuery"])

      user_id = context.user.id |> to_string()

      assert %{
               "description" => "some desc",
               "id" => _,
               "isPublic" => true,
               "name" => "MyQuery",
               "settings" => %{"some_key" => [0, 1, 2, 3]},
               "sqlQueryParameters" => %{"slug" => "bitcoin"},
               "sqlQueryText" =>
                 "SELECT * FROM intraday_metrics WHERE asset_id = get_asset_id({{slug}})",
               "user" => %{"id" => ^user_id}
             } = sql_query
    end

    test "update", context do
      sql_query_id =
        execute_sql_query_mutation(context.conn, :create_sql_query)
        |> get_in(["data", "createSqlQuery", "id"])

      sql_query =
        execute_sql_query_mutation(context.conn, :update_sql_query, %{
          id: sql_query_id,
          name: "New Query Name",
          description: "some desc - update",
          is_public: false,
          sql_query_text: "SELECT * FROM intraday_metrics WHERE asset_id = 123 LIMIT {{limit}}",
          sql_query_parameters: %{limit: 10}
        })
        |> get_in(["data", "updateSqlQuery"])

      user_id = context.user.id |> to_string()

      # The API returns the updated version
      assert assert %{
                      "description" => "some desc - update",
                      "id" => _,
                      "name" => "New Query Name",
                      "settings" => %{"some_key" => [0, 1, 2, 3]},
                      "sqlQueryParameters" => %{"limit" => 10},
                      "sqlQueryText" =>
                        "SELECT * FROM intraday_metrics WHERE asset_id = 123 LIMIT {{limit}}",
                      "user" => %{"id" => ^user_id}
                    } = sql_query

      # The updated version is persisted in the DB
      {:ok, fetched_query} = Sanbase.Queries.get_query(sql_query_id, context.user.id)
      assert fetched_query.name == "New Query Name"
      assert fetched_query.description == "some desc - update"
      assert fetched_query.is_public == false

      assert fetched_query.sql_query_text ==
               "SELECT * FROM intraday_metrics WHERE asset_id = 123 LIMIT {{limit}}"

      assert fetched_query.sql_query_parameters == %{"limit" => 10}
    end

    test "delete", context do
      sql_query_id =
        execute_sql_query_mutation(context.conn, :create_sql_query)
        |> get_in(["data", "createSqlQuery", "id"])

      # query exists
      assert {:ok, _} = Sanbase.Queries.get_query(sql_query_id, context.user.id)

      execute_sql_query_mutation(context.conn, :delete_sql_query, %{id: sql_query_id})

      # query  no longer exists
      assert {:error, error_msg} = Sanbase.Queries.get_query(sql_query_id, context.user.id)
      assert error_msg =~ "Query does not exist or you don't have access to it"
    end
  end

  describe "CRUD Dashboards APIs" do
    test "create", context do
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

    test "get", context do
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
               "queries" => [],
               "user" => %{"id" => ^user_id}
             } = result
    end

    test "delete", context do
      dashboard_id =
        execute_dashboard_mutation(context.conn, :create_dashboard)
        |> get_in(["data", "createDashboard", "id"])

      execute_dashboard_mutation(context.conn, :delete_dashboard, %{id: dashboard_id})

      assert {:error, error_msg} = Sanbase.Dashboards.get_dashboard(dashboard_id, context.user.id)
      assert error_msg =~ "does not exist"
    end

    test "parameters", context do
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

  describe "Dashboards Text Widget" do
    test "create", context do
      {:ok, %{id: dashboard_id}} =
        Sanbase.Dashboards.create_dashboard(%{name: "My Dashboard"}, context.user.id)

      # The dashboard mutation can run any mutation that returns a dashboard as a result
      result =
        execute_dashboard_text_widget_mutation(context.conn, :add_dashboard_text_widget, %{
          dashboard_id: dashboard_id,
          name: "My First Text Widget",
          description: "desc",
          body: "body"
        })
        |> get_in(["data", "addDashboardTextWidget"])

      assert %{
               "id" => ^dashboard_id,
               "name" => "My Dashboard",
               "queries" => [],
               "settings" => %{},
               "textWidgets" => [
                 %{
                   "body" => "body",
                   "description" => "desc",
                   "id" => <<_::binary>>,
                   "name" => "My First Text Widget"
                 }
               ],
               "user" => %{"id" => _}
             } = result["dashboard"]

      {:ok, fetched_dashboard} = Sanbase.Dashboards.get_dashboard(dashboard_id, context.user.id)

      assert length(fetched_dashboard.text_widgets) == 1
      [text_widget] = fetched_dashboard.text_widgets
      assert %{body: "body", description: "desc", name: "My First Text Widget"} = text_widget
    end

    test "update", context do
      {:ok, %{id: dashboard_id}} =
        Sanbase.Dashboards.create_dashboard(%{name: "My Dashboard"}, context.user.id)

      {:ok, %{text_widget: %{id: text_widget_id}}} =
        Sanbase.Dashboards.add_text_widget(dashboard_id, context.user.id, %{
          name: "name",
          description: "description",
          body: "body"
        })

      # The dashboard mutation can run any mutation that returns a dashboard as a result
      result =
        execute_dashboard_text_widget_mutation(context.conn, :update_dashboard_text_widget, %{
          dashboard_id: dashboard_id,
          text_widget_id: text_widget_id,
          name: "Updated name",
          description: "Updated desc"
        })
        |> get_in(["data", "updateDashboardTextWidget"])

      assert %{
               "id" => ^dashboard_id,
               "name" => "My Dashboard",
               "queries" => [],
               "settings" => %{},
               "textWidgets" => [
                 %{
                   "id" => ^text_widget_id,
                   "body" => "body",
                   "description" => "Updated desc",
                   "name" => "Updated name"
                 }
               ]
             } = result["dashboard"]

      assert %{
               "id" => ^text_widget_id,
               "body" => "body",
               "description" => "Updated desc",
               "name" => "Updated name"
             } = result["textWidget"]

      {:ok, fetched_dashboard} = Sanbase.Dashboards.get_dashboard(dashboard_id, context.user.id)

      assert length(fetched_dashboard.text_widgets) == 1
      [text_widget] = fetched_dashboard.text_widgets
      assert %{body: "body", description: "Updated desc", name: "Updated name"} = text_widget
    end

    test "delete", context do
      {:ok, %{id: dashboard_id}} =
        Sanbase.Dashboards.create_dashboard(%{name: "My Dashboard"}, context.user.id)

      {:ok, %{text_widget: %{id: text_widget_id}}} =
        Sanbase.Dashboards.add_text_widget(dashboard_id, context.user.id, %{
          name: "name",
          description: "description",
          body: "body"
        })

      result =
        execute_dashboard_text_widget_mutation(context.conn, :delete_dashboard_text_widget, %{
          dashboard_id: dashboard_id,
          text_widget_id: text_widget_id
        })
        |> get_in(["data", "deleteDashboardTextWidget"])

      assert %{
               "id" => ^dashboard_id,
               "name" => "My Dashboard",
               "queries" => [],
               "settings" => %{},
               "textWidgets" => []
             } = result["dashboard"]

      assert %{
               "id" => ^text_widget_id,
               "body" => "body",
               "description" => "description",
               "name" => "name"
             } = result["textWidget"]

      {:ok, fetched_dashboard} = Sanbase.Dashboards.get_dashboard(dashboard_id, context.user.id)

      assert length(fetched_dashboard.text_widgets) == 0
    end
  end

  describe "Run Queries" do
    test "run raw sql query", context do
      # In test env the storing runs not async and there's a 7500ms sleep
      Application.put_env(:__sanbase_queries__, :__store_execution_details__, false)

      on_exit(fn -> Application.delete_env(:__sanbase_queries__, :__store_execution_details__) end)

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
        args = %{
          sql_query_text:
            "SELECT * FROM intraday_metrics WHERE asset_id = get_asset_id({{slug}}) LIMIT {{limit}}",
          sql_query_parameters: %{slug: "bitcoin", limit: 2}
        }

        result =
          run_sql_query(context.conn, :run_raw_sql_query, args)
          |> get_in(["data", "runRawSqlQuery"])

        assert %{
                 "clickhouseQueryId" => "177a5a3d-072b-48ac-8cf5-d8375c8314ef",
                 "columns" => ["asset_id", "metric_id", "dt", "value", "computed_at"],
                 "columnTypes" => ["UInt64", "UInt64", "DateTime", "Float64", "DateTime"],
                 "rows" => [
                   [2503, 250, "2008-12-10T00:00:00Z", 0.0, "2020-02-28T15:18:42Z"],
                   [2503, 250, "2008-12-10T00:05:00Z", 0.0, "2020-02-28T15:18:42Z"]
                 ],
                 "summary" => %{
                   "read_bytes" => 0.0,
                   "read_rows" => 0.0,
                   "total_rows_to_read" => 0.0,
                   "written_bytes" => 0.0,
                   "written_rows" => 0.0
                 }
               } = result
      end)
    end

    test "run sql query by id", context do
      # In test env the storing runs not async and there's a 7500ms sleep
      Application.put_env(:__sanbase_queries__, :__store_execution_details__, false)

      on_exit(fn -> Application.delete_env(:__sanbase_queries__, :__store_execution_details__) end)

      {:ok, query} = create_query(context.user.id)

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
        result =
          run_sql_query(context.conn, :run_sql_query, %{id: query.id})
          |> get_in(["data", "runSqlQuery"])

        # Use match `=` operator to avoid checking the queryStartTime and queryEndTime
        assert %{
                 "clickhouseQueryId" => "177a5a3d-072b-48ac-8cf5-d8375c8314ef",
                 "columns" => ["asset_id", "metric_id", "dt", "value", "computed_at"],
                 "columnTypes" => ["UInt64", "UInt64", "DateTime", "Float64", "DateTime"],
                 "rows" => [
                   [2503, 250, "2008-12-10T00:00:00Z", 0.0, "2020-02-28T15:18:42Z"],
                   [2503, 250, "2008-12-10T00:05:00Z", 0.0, "2020-02-28T15:18:42Z"]
                 ],
                 "summary" => %{
                   "read_bytes" => 0.0,
                   "read_rows" => 0.0,
                   "total_rows_to_read" => 0.0,
                   "written_bytes" => 0.0,
                   "written_rows" => 0.0
                 }
               } = result
      end)
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
      override =
        execute_global_parameter_mutation(
          context.conn,
          :add_dashboard_global_parameter_override,
          %{
            dashboard_id: dashboard.id,
            dashboard_query_mapping_id: mapping["id"],
            dashboard_parameter_key: "slug",
            query_parameter_key: "slug"
          }
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
                   [2503, 250, "2008-12-10T00:00:00Z", 0.0, "2020-02-28T15:18:42Z"],
                   [2503, 250, "2008-12-10T00:05:00Z", 0.0, "2020-02-28T15:18:42Z"]
                 ],
                 "summary" => %{
                   "read_bytes" => 0.0,
                   "read_rows" => 0.0,
                   "total_rows_to_read" => 0.0,
                   "written_bytes" => 0.0,
                   "written_rows" => 0.0
                 }
               } = result
      end)
    end

    test "get credits stats after run", context do
      # In test env the storing runs not async and there's a 7500ms sleep, put it to 0
      # we need to store it here so we can later retrieve the executions info
      Application.put_env(:__sanbase_queries__, :__wait_fetching_details_ms_, 0)

      on_exit(fn -> Application.delete_env(:__sanbase_queries__, :__wait_fetching_details_ms_) end)

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
        args = %{
          sql_query_text: "SELECT * FROM intraday_metrics LIMIT {{limit}}",
          sql_query_parameters: %{limit: 2}
        }

        run_sql_query(context.conn, :run_raw_sql_query, args)

        stats =
          get_current_user_credits_stats(context.conn)
          |> get_in(["data", "currentUser", "queriesExecutionsInfo"])

        assert stats == %{
                 "creditsAvailalbeMonth" => 5000,
                 "creditsRemainingMonth" => 4999,
                 "creditsSpentMonth" => 1,
                 "queriesExecutedDay" => 1,
                 "queriesExecutedDayLimit" => 10,
                 "queriesExecutedHour" => 1,
                 "queriesExecutedHourLimit" => 5,
                 "queriesExecutedMinute" => 1,
                 "queriesExecutedMinuteLimit" => 1,
                 "queriesExecutedMonth" => 1
               }
      end)
    end

    defp get_current_user_credits_stats(conn) do
      conn
      |> post(
        "/graphql",
        query_skeleton("""
        {
          currentUser {
            queriesExecutionsInfo {
              # credits info
              creditsAvailalbeMonth
              creditsSpentMonth
              creditsRemainingMonth
              # queries executed
              queriesExecutedMonth
              queriesExecutedDay
              queriesExecutedHour
              queriesExecutedMinute
              # queries executions limits
              queriesExecutedDayLimit
              queriesExecutedHourLimit
              queriesExecutedMinuteLimit
            }
          }
        }
        """)
      )
      |> json_response(200)
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
          store_dashboard_query_execution(context.conn, %{
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
                       [2503, 250, "2008-12-10T00:00:00Z", 0.0, "2020-02-28T15:18:42Z"],
                       [2503, 250, "2008-12-10T00:05:00Z", 0.0, "2020-02-28T15:18:42Z"]
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
                       [2503, 250, "2008-12-10T00:00:00Z", 0.0, "2020-02-28T15:18:42Z"],
                       [2503, 250, "2008-12-10T00:05:00Z", 0.0, "2020-02-28T15:18:42Z"]
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

  describe "get clickhouse database information" do
    test "get available clickhouse tables API", context do
      query = """
      {
        getAvailableClickhouseTables{
          table
          description
          columns
          engine
          orderBy
          partitionBy
        }
      }
      """

      result =
        context.conn
        |> post("/graphql", query_skeleton(query))
        |> json_response(200)
        |> get_in(["data", "getAvailableClickhouseTables"])

      assert %{
               "columns" => %{
                 "base_asset" => "LowCardinality(String)",
                 "dt" => "DateTime",
                 "price" => "Float64",
                 "quote_asset" => "LowCardinality(String)",
                 "source" => "LowCardinality(String)"
               },
               "description" =>
                 "Provide price_usd, price_btc, volume_usd and marketcap_usd metrics for assets",
               "engine" => "ReplicatedReplacingMergeTree",
               "orderBy" => ["base_asset", "quote_asset", "source", "dt"],
               "partitionBy" => "toYYYYMM(dt)",
               "table" => "asset_prices_v3"
             } in result

      assert %{
               "columns" => %{
                 "assetRefId" => "UInt64",
                 "blockNumber" => "UInt32",
                 "contract" => "LowCardinality(String)",
                 "dt" => "DateTime",
                 "from" => "LowCardinality(String)",
                 "logIndex" => "UInt32",
                 "primaryKey" => "UInt64",
                 "to" => "LowCardinality(String)",
                 "transactionHash" => "String",
                 "value" => "Float64",
                 "valueExactBase36" => "String"
               },
               "description" => "Provide the on-chain transfers for Ethereum itself",
               "engine" => "Distributed",
               "orderBy" => ["from", "type", "to", "dt", "transactionHash", "primaryKey"],
               "partitionBy" => "toStartOfMonth(dt)",
               "table" => "erc20_transfers"
             } in result
    end

    test "get clickhouse database metadata", context do
      query = """
      {
        getClickhouseDatabaseMetadata{
          columns{ name isInSortingKey isInPartitionKey }
          tables{ name partitionKey sortingKey primaryKey }
          functions{ name origin }
        }
      }
      """

      mock_fun =
        [
          # mock columns response
          fn ->
            {:ok,
             %{
               rows: [
                 ["asset_metadata", "asset_id", "UInt64", 0, 1, 1],
                 ["asset_metadata", "computed_at", "DateTime", 0, 0, 0]
               ]
             }}
          end,
          # mock functions response
          fn -> {:ok, %{rows: [["logTrace", "System"], ["get_asset_id", "SQLUserDefined"]]}} end,
          # mock tables response
          fn ->
            {:ok,
             %{
               rows: [
                 ["asset_metadata", "ReplicatedReplacingMergeTree", "", "asset_id", "asset_id"],
                 [
                   "asset_price_pairs_only",
                   "ReplicatedReplacingMergeTree",
                   "toYYYYMM(dt)",
                   "base_asset, quote_asset, source, dt",
                   "base_asset, quote_asset, source, dt"
                 ]
               ]
             }}
          end
        ]
        |> Sanbase.Mock.wrap_consecutives(arity: 2)

      Sanbase.Mock.prepare_mock(Sanbase.ClickhouseRepo, :query, mock_fun)
      |> Sanbase.Mock.run_with_mocks(fn ->
        metadata =
          post(context.conn, "/graphql", query_skeleton(query))
          |> json_response(200)
          |> get_in(["data", "getClickhouseDatabaseMetadata"])

        assert metadata == %{
                 "columns" => [
                   %{"isInPartitionKey" => false, "isInSortingKey" => true, "name" => "asset_id"},
                   %{
                     "isInPartitionKey" => false,
                     "isInSortingKey" => false,
                     "name" => "computed_at"
                   }
                 ],
                 "functions" => [
                   %{"name" => "logTrace", "origin" => "System"},
                   %{"name" => "get_asset_id", "origin" => "SQLUserDefined"}
                 ],
                 "tables" => [
                   %{
                     "name" => "asset_metadata",
                     "partitionKey" => "",
                     "primaryKey" => "asset_id",
                     "sortingKey" => "asset_id"
                   },
                   %{
                     "name" => "asset_price_pairs_only",
                     "partitionKey" => "toYYYYMM(dt)",
                     "primaryKey" => "base_asset, quote_asset, source, dt",
                     "sortingKey" => "base_asset, quote_asset, source, dt"
                   }
                 ]
               }
      end)
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

  defp execute_dashboard_mutation(conn, mutation, args \\ nil) do
    args =
      args ||
        %{
          name: "MyDashboard",
          description: "some text",
          is_public: true,
          settings: %{"some_key" => [0, 1, 2, 3]}
        }

    mutation_name = mutation |> Inflex.camelize(:lower)

    mutation = """
    mutation {
      #{mutation_name}(#{map_to_args(args)}) {
        id
        name
        description
        user { id }
        queries { id }
        textWidgets { id name description body }
        settings
      }
    }
    """

    conn
    |> post("/graphql", mutation_skeleton(mutation))
    |> json_response(200)
  end

  defp execute_dashboard_text_widget_mutation(conn, mutation, args) do
    mutation_name = mutation |> Inflex.camelize(:lower)

    mutation = """
    mutation {
      #{mutation_name}(#{map_to_args(args)}){
        dashboard {
          id
          name
          description
          user { id }
          queries { id }
          textWidgets { id name description body }
          settings
        }
        textWidget {
          id
          name
          description
          body
        }
      }
    }
    """

    conn
    |> post("/graphql", mutation_skeleton(mutation))
    |> json_response(200)
  end

  defp execute_sql_query_mutation(conn, mutation, args \\ nil) do
    args =
      args ||
        %{
          name: "MyQuery",
          description: "some desc",
          is_public: true,
          sql_query_text:
            "SELECT * FROM intraday_metrics WHERE asset_id = get_asset_id({{slug}})",
          sql_query_parameters: %{slug: "bitcoin"},
          settings: %{"some_key" => [0, 1, 2, 3]}
        }

    mutation_name = mutation |> Inflex.camelize(:lower)

    mutation = """
    mutation {
      #{mutation_name}(#{map_to_args(args)}){
        id
        name
        description
        user{ id }
        sqlQueryText
        sqlQueryParameters
        settings
      }
    }
    """

    conn
    |> post("/graphql", mutation_skeleton(mutation))
    |> json_response(200)
  end

  defp execute_global_parameter_mutation(conn, mutation, args) do
    mutation_name = mutation |> Inflex.camelize(:lower)

    mutation = """
    mutation{
      #{mutation_name}(#{map_to_args(args)}){
        parameters
      }
    }
    """

    conn
    |> post("/graphql", mutation_skeleton(mutation))
    |> json_response(200)
  end

  defp execute_dashboard_query_mutation(conn, mutation, args) do
    mutation_name = mutation |> Inflex.camelize(:lower)

    mutation = """
    mutation {
      #{mutation_name}(#{map_to_args(args)}){
        id
        query{ id sqlQueryText sqlQueryParameters }
        dashboard { id parameters }
        settings
      }
    }
    """

    conn
    |> post("/graphql", mutation_skeleton(mutation))
    |> json_response(200)
  end

  defp run_sql_query(conn, query, args) do
    query_name = query |> Inflex.camelize(:lower)

    mutation = """
    {
      #{query_name}(#{map_to_args(args)}){
        queryId
        dashboardQueryMappingId
        clickhouseQueryId
        columnTypes
        columns
        rows
        summary
        queryStartTime
        queryEndTime
      }
    }
    """

    conn
    |> post("/graphql", mutation_skeleton(mutation))
    |> json_response(200)
  end

  defp store_dashboard_query_execution(conn, args) do
    mutation = """
    mutation{
      storeDashboardQueryExecution(#{map_to_args(args)}){
        queries{
          queryId
          dashboardQueryMappingId
          clickhouseQueryId
          columns
          rows
          columnTypes
          queryStartTime
          queryEndTime
        }
      }
    }
    """

    conn
    |> post("/graphql", mutation_skeleton(mutation))
    |> json_response(200)
  end

  defp get_cached_dashboard_queries_executions(conn, args) do
    query = """
    {
      getCachedDashboardQueriesExecutions(#{map_to_args(args)}){
        queries{
          queryId
          dashboardQueryMappingId
          clickhouseQueryId
          columnTypes
          columns
          rows
          queryStartTime
          queryEndTime
        }
      }
    }
    """

    conn
    |> post("/graphql", query_skeleton(query))
    |> json_response(200)
  end

  defp get_dashboard(conn, dashboard_id) do
    query = """
    {
      getDashboard(id: #{dashboard_id}){
        id
        name
        description
        isPublic
        settings
        user{ id }
        queries {
          id
          sqlQueryText
          sqlQueryParameters
          settings
          user{ id }
        }
        votes {
          totalVotes
        }
      }
    }
    """

    conn
    |> post("/graphql", query_skeleton(query))
    |> json_response(200)
  end

  defp get_sql_query(conn, query_id) do
    query = """
    {
      getSqlQuery(id: #{query_id}){
        id
        name
        description
        isPublic
        settings
        user{ id }
        sqlQueryText
        sqlQueryParameters
        votes {
          totalVotes
        }
      }
    }
    """

    conn
    |> post("/graphql", query_skeleton(query))
    |> json_response(200)
  end

  defp mocked_clickhouse_result() do
    %Clickhousex.Result{
      columns: ["asset_id", "metric_id", "dt", "value", "computed_at"],
      column_types: ["UInt64", "UInt64", "DateTime", "Float64", "DateTime"],
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

  defp mocked_execution_details_result() do
    %Clickhousex.Result{
      query_id: "1774C4BC91E058D4",
      summary: %{
        "read_bytes" => "5069080",
        "read_rows" => "167990",
        "result_bytes" => "0",
        "result_rows" => "0",
        "total_rows_to_read" => "167990",
        "written_bytes" => "0",
        "written_rows" => "0"
      },
      command: :selected,
      columns: [
        "read_compressed_gb",
        "cpu_time_microseconds",
        "query_duration_ms",
        "memory_usage_gb",
        "read_rows",
        "read_gb",
        "result_rows",
        "result_gb"
      ],
      column_types: [
        "Float64",
        "UInt64",
        "UInt64",
        "Float64",
        "UInt64",
        "Float64",
        "UInt64",
        "Float64"
      ],
      rows: [
        [
          # read_compressed_gb
          0.001110738143324852,
          # cpu_time_microseconds
          101_200,
          # query_duration_ms
          47,
          # memory_usage_gb
          0.03739274851977825,
          # read_rows
          364_923,
          # read_gb
          0.01087852381169796,
          # result_rows
          2,
          # result_gb
          2.980232238769531e-7
        ]
      ],
      num_rows: 1
    }
  end
end
