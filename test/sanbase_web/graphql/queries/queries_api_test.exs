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
  end

  describe "run queries" do
    test "compute raw clickhouse query", context do
      args = %{
        query:
          "SELECT * FROM intraday_metrics WHERE asset_id IN (SELECT asset_id FROM asset_metadata WHERE name = {{slug}}) LIMIT {{limit}}",
        parameters: %{slug: "bitcoin", limit: 2},
        map_as_input_object: true
      }

      query = """
      {
        computeRawClickhouseQuery(#{map_to_args(args)}){
          columns
          columnTypes
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
          |> post("/graphql", query_skeleton(query))
          |> json_response(200)
          |> get_in(["data", "computeRawClickhouseQuery"])

        assert result == %{
                 "clickhouseQueryId" => "177a5a3d-072b-48ac-8cf5-d8375c8314ef",
                 "columns" => ["asset_id", "metric_id", "dt", "value", "computed_at"],
                 "columnTypes" => ["UInt64", "UInt64", "DateTime", "Float64", "DateTime"],
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
      #{mutation_name}(#{map_to_args(args)}){
        id
        name
        description
        user{ id }
        queries { id }
        settings
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
end
