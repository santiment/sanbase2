defmodule SanbaseWeb.Graphql.QueriesApiTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import Sanbase.QueriesMocks
  import SanbaseWeb.Graphql.TestHelpers
  import SanbaseWeb.QueriesApiHelpers

  setup do
    user = insert(:user)
    user2 = insert(:user)
    conn = setup_jwt_auth(build_conn(), user)
    conn2 = setup_jwt_auth(build_conn(), user2)

    %{conn: conn, conn2: conn2, user: user, user2: user2}
  end

  describe "voting" do
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
    test "create query", context do
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

    test "get query", context do
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

    test "update query", context do
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

    test "delete query", context do
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
                 "creditsAvailalbeMonth" => 500,
                 "creditsRemainingMonth" => 499,
                 "creditsSpentMonth" => 1,
                 "queriesExecutedDay" => 1,
                 "queriesExecutedDayLimit" => 500,
                 "queriesExecutedHour" => 1,
                 "queriesExecutedHourLimit" => 200,
                 "queriesExecutedMinute" => 1,
                 "queriesExecutedMinuteLimit" => 20,
                 "queriesExecutedMonth" => 1
               }
      end)
    end

    test "get dynamic repo and credits stats after run for business max user", context do
      insert(:subscription_business_max_monthly, user: context.user)
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

        assert Process.get(:queries_dynamic_repo) == Sanbase.ClickhouseRepo.BusinessMaxUser

        assert stats == %{
                 "creditsAvailalbeMonth" => 500_000,
                 "creditsRemainingMonth" => 499_999,
                 "creditsSpentMonth" => 1,
                 "queriesExecutedDay" => 1,
                 "queriesExecutedDayLimit" => 15000,
                 "queriesExecutedHour" => 1,
                 "queriesExecutedHourLimit" => 3000,
                 "queriesExecutedMinute" => 1,
                 "queriesExecutedMinuteLimit" => 100,
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
    test "cache query executions", context do
      Application.put_env(:__sanbase_queries__, :__store_execution_details__, false)

      on_exit(fn -> Application.delete_env(:__sanbase_queries__, :__store_execution_details__) end)

      {:ok, query} = create_query(context.user.id)

      Sanbase.Mock.prepare_mock2(
        &Sanbase.ClickhouseRepo.query/2,
        {:ok, mocked_clickhouse_result()}
      )
      |> Sanbase.Mock.run_with_mocks(fn ->
        result =
          run_sql_query(context.conn, :run_sql_query, %{id: query.id})
          |> get_in(["data", "runSqlQuery"])

        compressed_and_encoded_result =
          result |> Jason.encode!() |> :zlib.gzip() |> Base.encode64()

        # The owner cache

        cache_result =
          execute_cache_query_execution_mutation(context.conn, %{
            query_id: query.id,
            compressed_query_execution_result: compressed_and_encoded_result
          })
          |> get_in(["data", "storeQueryExecution"])

        assert cache_result == true

        # The user cache

        cache_result =
          execute_cache_query_execution_mutation(context.conn2, %{
            query_id: query.id,
            compressed_query_execution_result: compressed_and_encoded_result
          })
          |> get_in(["data", "storeQueryExecution"])

        assert cache_result == true

        # Get the user own cache the owner of the query cache
        caches =
          execute_get_cached_query_executions_query(context.conn2, %{query_id: query.id})
          |> get_in(["data", "getCachedQueryExecutions"])

        # Only we cached
        assert length(caches) == 2

        owner_user_id = context.user.id |> to_string()
        own_user_id = context.user.id |> to_string()

        owner_cache = caches |> Enum.find(&(&1["user"]["id"] == owner_user_id))
        own_cache = caches |> Enum.find(&(&1["user"]["id"] == own_user_id))

        # Check the owner's cache of the query
        assert %{
                 "insertedAt" => _,
                 "isQueryHashMatching" => true,
                 "result" => %{
                   "columnTypes" => ["UInt64", "UInt64", "DateTime", "Float64", "DateTime"],
                   "columns" => ["asset_id", "metric_id", "dt", "value", "computed_at"],
                   "rows" => [
                     [2503, 250, "2008-12-10T00:00:00Z", +0.0, "2020-02-28T15:18:42Z"],
                     [2503, 250, "2008-12-10T00:05:00Z", +0.0, "2020-02-28T15:18:42Z"]
                   ]
                 },
                 "user" => %{"id" => ^owner_user_id}
               } = owner_cache

        # Check the querying user's cache of the query
        assert %{
                 "insertedAt" => _,
                 "isQueryHashMatching" => true,
                 "result" => %{
                   "columnTypes" => ["UInt64", "UInt64", "DateTime", "Float64", "DateTime"],
                   "columns" => ["asset_id", "metric_id", "dt", "value", "computed_at"],
                   "rows" => [
                     [2503, 250, "2008-12-10T00:00:00Z", +0.0, "2020-02-28T15:18:42Z"],
                     [2503, 250, "2008-12-10T00:05:00Z", +0.0, "2020-02-28T15:18:42Z"]
                   ]
                 },
                 "user" => %{"id" => ^own_user_id}
               } = own_cache
      end)
    end

    test "Cannot cache another user private query", context do
      {:ok, query} = Sanbase.Queries.create_query(%{is_public: false}, context.user2.id)

      # Not a valid base64 encoded string
      error_msg =
        execute_cache_query_execution_mutation(context.conn, %{
          query_id: query.id,
          compressed_query_execution_result: "xxxxasd12309uaksdl!@876@#_тест_Тест"
        })
        |> get_in(["errors", Access.at(0), "message"])

      assert error_msg =~ "The provided value is not a valid base64-encoded binary"

      # Not a valid GZIP
      error_msg =
        execute_cache_query_execution_mutation(context.conn, %{
          query_id: query.id,
          compressed_query_execution_result: "hehe" |> Base.encode64()
        })
        |> get_in(["errors", Access.at(0), "message"])

      assert error_msg =~ "The provided value is not a valid gzip binary"

      # Valid gzip, but not valid query result
      result =
        %{columns: ["a"], rows: [2, 3]} |> Jason.encode!() |> :zlib.gzip() |> Base.encode64()

      error_msg =
        execute_cache_query_execution_mutation(context.conn, %{
          query_id: query.id,
          compressed_query_execution_result: result
        })
        |> get_in(["errors", Access.at(0), "message"])

      assert error_msg ==
               "The following result fields are not provided: clickhouseQueryId, columnTypes, queryEndTime, queryId, queryStartTime, summary"
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
end
