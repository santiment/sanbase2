defmodule Sanbase.QueriesTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import Mock, only: [assert_called: 1]

  alias Sanbase.Queries

  setup do
    user = insert(:user)
    user2 = insert(:user)

    assert {:ok, query} =
             Queries.create_query(
               %{
                 is_public: true,
                 sql_query_text: "SELECT * FROM metrics WHERE slug = {{slug}} LIMIT {{limit}}",
                 sql_query_parameters: %{"slug" => "ethereum", "limit" => 20}
               },
               user.id
             )

    query_metadata = Sanbase.Queries.QueryMetadata.from_local_dev(user.id)

    sql_query_text =
      "SELECT * FROM intraday_metrics WHERE asset_id = get_asset_id({{slug}}) LIMIT {{limit}}"

    sql_query_parameters = %{slug: "bitcoin", limit: 2}

    {:ok, dashboard} =
      Sanbase.Dashboards.create_dashboard(%{name: "My dashboard", is_public: false}, user.id)

    {:ok, dashboard_query_mapping} =
      Sanbase.Dashboards.add_query_to_dashboard(dashboard.id, query.id, user.id)

    %{
      user: user,
      user2: user2,
      query: query,
      dashboard: dashboard,
      dashboard_query_mapping: dashboard_query_mapping,
      query_metadata: query_metadata,
      sql_query_text: sql_query_text,
      sql_query_parameters: sql_query_parameters
    }
  end

  describe "Queries CRUD" do
    test "create", %{user: user} do
      assert {:ok, query} =
               Queries.create_query(
                 %{
                   sql_query_text: "SELECT * FROM metrics WHERE slug = {{slug}} LIMIT {{limit}}",
                   sql_query_parameters: %{"slug" => "ethereum", "limit" => 20}
                 },
                 user.id
               )

      assert {:ok, fetched_query} = Queries.get_query(query.id, user.id)

      assert fetched_query.sql_query_text ==
               "SELECT * FROM metrics WHERE slug = {{slug}} LIMIT {{limit}}"

      assert fetched_query.sql_query_parameters == %{"slug" => "ethereum", "limit" => 20}

      assert fetched_query.user_id == user.id
      assert fetched_query.id == query.id
      assert fetched_query.uuid == query.uuid
    end

    test "get query", %{user: user, query: query} do
      {:ok, fetched_query} = Queries.get_query(query.id, user.id)

      assert query.id == fetched_query.id
      assert query.uuid == fetched_query.uuid
      assert query.origin_id == fetched_query.origin_id
      assert query.sql_query_text == fetched_query.sql_query_text
      assert query.sql_query_parameters == fetched_query.sql_query_parameters
      assert query.user_id == fetched_query.user_id
      assert query.settings == fetched_query.settings
    end

    test "get dashboard query", %{user: user, dashboard: dashboard, query: query} do
      {:ok, dashboard_query_mapping} =
        Sanbase.Dashboards.add_query_to_dashboard(dashboard.id, query.id, user.id)

      {:ok, dashboard} =
        Sanbase.Dashboards.add_global_parameter(dashboard.id, user.id,
          key: "slug",
          value: "bitcoin"
        )

      {:ok, _} =
        Sanbase.Dashboards.add_global_parameter_override(
          dashboard.id,
          dashboard_query_mapping.id,
          user.id,
          query_parameter_key: "slug",
          dashboard_parameter_key: "slug"
        )

      {:ok, query} =
        Sanbase.Queries.get_dashboard_query(dashboard.id, dashboard_query_mapping.id, user.id)

      assert query.sql_query_parameters == %{"slug" => "bitcoin", "limit" => 20}
    end

    test "can update own query", %{user: user, query: query} do
      assert {:ok, updated_query} =
               Queries.update_query(
                 query.id,
                 %{
                   name: "My updated dashboard",
                   sql_query_text: "SELECT * FROM metrics WHERE slug IN {{slugs}}",
                   sql_query_parameters: %{"slugs" => ["ethereum", "bitcoin"]}
                 },
                 user.id
               )

      # The returned result is updated
      assert updated_query.id == query.id
      assert updated_query.name == "My updated dashboard"
      assert updated_query.sql_query_text == "SELECT * FROM metrics WHERE slug IN {{slugs}}"
      assert updated_query.sql_query_parameters == %{"slugs" => ["ethereum", "bitcoin"]}

      # The updates are persisted
      assert {:ok, fetched_query} = Queries.get_query(query.id, user.id)

      assert fetched_query.id == query.id
      assert fetched_query.name == "My updated dashboard"
      assert fetched_query.sql_query_text == "SELECT * FROM metrics WHERE slug IN {{slugs}}"
      assert fetched_query.sql_query_parameters == %{"slugs" => ["ethereum", "bitcoin"]}
    end

    test "cannot update other user query", %{query: query, user2: user2} do
      assert {:error, error_msg} =
               Queries.update_query(
                 query.id,
                 %{
                   name: "My updated dashboard",
                   sql_query_text: "SELECT * FROM metrics WHERE slug IN {{slugs}}",
                   sql_query_parameters: %{"slugs" => ["ethereum", "bitcoin"]}
                 },
                 user2.id
               )

      assert error_msg =~ "does not exist or it belongs to another user"
    end

    test "get all user queries", %{user: user, query: query} do
      assert {:ok, query2} = Queries.create_query(%{}, user.id)
      assert {:ok, query3} = Queries.create_query(%{}, user.id)
      assert {:ok, list} = Queries.get_user_queries(user.id, user.id, page: 1, page_size: 10)

      assert length(list) == 3

      assert Enum.map(list, & &1.id) |> Enum.sort() ==
               [query.id, query2.id, query3.id] |> Enum.sort()
    end

    test "get all public queries", %{user: user, user2: user2, query: query} do
      {:ok, query2} = Sanbase.Queries.create_query(%{is_public: true}, user.id)
      {:ok, _} = Sanbase.Queries.create_query(%{is_public: false}, user.id)
      {:ok, query3} = Sanbase.Queries.create_query(%{is_public: true}, user2.id)
      {:ok, _} = Sanbase.Queries.create_query(%{is_public: false}, user2.id)

      {:ok, queries} = Sanbase.Queries.get_public_queries(page: 1, page_size: 10)

      assert length(queries) == 3

      queries_ids = [query.id, query2.id, query3.id]

      Enum.each(queries, fn q ->
        assert q.id in queries_ids
        assert q.is_public == true
      end)
    end
  end

  describe "Query Execution Details" do
    test "fetch execution details after running a query ", context do
      %{
        query: %{id: query_id} = query,
        user: %{id: user_id} = user,
        query_metadata: query_metadata
      } = context

      # The first function returns the result of the query itself.
      # The second function returns the execution stats of the query.
      mock_fun =
        Sanbase.Mock.wrap_consecutives(
          [
            fn -> {:ok, ch_result_mock()} end,
            fn -> {:ok, execution_details_mock()} end
          ],
          arity: 2
        )

      Sanbase.Mock.prepare_mock(Sanbase.ClickhouseRepo, :query, mock_fun)
      |> Sanbase.Mock.run_with_mocks(fn ->
        # In test case the execution details are avaialble immediately
        # as the result is mocked. The store_executioN_details is true
        # by default, although here it's set so it can be also tested
        run_query_opts = [store_execution_details: true, wait_fetching_details_ms: 0]
        # Run a query by id
        {:ok, _result} = Sanbase.Queries.run_query(query, user, query_metadata, run_query_opts)

        # Ensure that the executions are sequentials. The storing of details is async
        # so it could happen that the details are reordered.
        Process.sleep(10)

        # Run a raw query
        ephemeral_query = Sanbase.Queries.get_ephemeral_query_struct("SELECT now()", %{}, user)

        {:ok, _result} =
          Sanbase.Queries.run_query(ephemeral_query, user, query_metadata, run_query_opts)

        Process.sleep(10)

        {:ok, executions} =
          Sanbase.Queries.get_user_query_executions(user.id, page: 1, page_size: 10)

        assert length(executions) == 2

        # The checks below differ only on the query_id. Assert that the query_id
        # is not nil, so in one case we record the query and it in the other case
        # it is nil
        assert query_id != nil

        # The executions are ordered by id in descending order. The later raw
        # query execution is first in the list
        [execution_raw_query, execution_by_id] = executions

        # Match against maps so we don't check some of the
        # unnecessary fields.
        assert %{
                 user_id: ^user_id,
                 query_id: ^query_id,
                 execution_details: %{
                   "cpu_time_microseconds" => 101_200,
                   "memory_usage_gb" => 0.037393,
                   "query_duration_ms" => 47,
                   "read_compressed_gb" => 0.001111,
                   "read_gb" => 0.010879,
                   "read_rows" => 364_923,
                   "result_gb" => +0.0,
                   "result_rows" => 2
                 },
                 credits_cost: 1
               } = execution_by_id

        assert %{
                 user_id: ^user_id,
                 query_id: nil,
                 execution_details: %{
                   "cpu_time_microseconds" => 101_200,
                   "memory_usage_gb" => 0.037393,
                   "query_duration_ms" => 47,
                   "read_compressed_gb" => 0.001111,
                   "read_gb" => 0.010879,
                   "read_rows" => 364_923,
                   "result_gb" => +0.0,
                   "result_rows" => 2
                 },
                 credits_cost: 1
               } = execution_raw_query
      end)
    end
  end

  describe "Run Queries" do
    test "run raw query", context do
      %{
        sql_query_text: sql_query_text,
        sql_query_parameters: sql_query_parameters,
        query_metadata: query_metadata,
        user: user
      } = context

      Sanbase.Mock.prepare_mock2(&Sanbase.ClickhouseRepo.query/2, {:ok, ch_result_mock()})
      |> Sanbase.Mock.run_with_mocks(fn ->
        query =
          Sanbase.Queries.get_ephemeral_query_struct(sql_query_text, sql_query_parameters, user)

        {:ok, result} =
          Sanbase.Queries.run_query(query, user, query_metadata, store_execution_details: false)

        assert %Sanbase.Queries.Executor.Result{
                 query_id: nil,
                 clickhouse_query_id: "1774C4BC91E05698",
                 summary: %{
                   "read_bytes" => 408_534.0,
                   "read_rows" => 12667.0,
                   "result_bytes" => +0.0,
                   "result_rows" => +0.0,
                   "total_rows_to_read" => 4475.0,
                   "written_bytes" => +0.0,
                   "written_rows" => +0.0
                 },
                 rows: [
                   [
                     1482,
                     1645,
                     ~U[1970-01-01 00:00:00Z],
                     0.045183932486757644,
                     ~U[2023-07-26 13:10:51Z]
                   ],
                   [
                     1482,
                     1647,
                     ~U[1970-01-01 00:00:00Z],
                     -0.13018891098082416,
                     ~U[2023-07-25 20:27:06Z]
                   ]
                 ],
                 compressed_rows: _,
                 columns: ["asset_id", "metric_id", "dt", "value", "computed_at"],
                 column_types: ["UInt64", "UInt64", "DateTime", "Float64", "DateTime"],
                 query_start_time: query_start_time,
                 query_end_time: query_end_time
               } = result

        assert Sanbase.TestUtils.datetime_close_to(Timex.now(), query_start_time, 2)
        assert Sanbase.TestUtils.datetime_close_to(Timex.now(), query_end_time, 2)
      end)
    end

    test "run query by id", context do
      %{
        query: %{id: query_id} = query,
        user: user,
        query_metadata: query_metadata
      } = context

      Sanbase.Mock.prepare_mock2(&Sanbase.ClickhouseRepo.query/2, {:ok, ch_result_mock()})
      |> Sanbase.Mock.run_with_mocks(fn ->
        {:ok, result} =
          Sanbase.Queries.run_query(query, user, query_metadata, store_execution_details: false)

        assert %Sanbase.Queries.Executor.Result{
                 query_id: ^query_id,
                 clickhouse_query_id: "1774C4BC91E05698",
                 summary: %{
                   "read_bytes" => 408_534.0,
                   "read_rows" => 12667.0,
                   "result_bytes" => +0.0,
                   "result_rows" => +0.0,
                   "total_rows_to_read" => 4475.0,
                   "written_bytes" => +0.0,
                   "written_rows" => +0.0
                 },
                 rows: [
                   [
                     1482,
                     1645,
                     ~U[1970-01-01 00:00:00Z],
                     0.045183932486757644,
                     ~U[2023-07-26 13:10:51Z]
                   ],
                   [
                     1482,
                     1647,
                     ~U[1970-01-01 00:00:00Z],
                     -0.13018891098082416,
                     ~U[2023-07-25 20:27:06Z]
                   ]
                 ],
                 compressed_rows: _,
                 columns: ["asset_id", "metric_id", "dt", "value", "computed_at"],
                 column_types: ["UInt64", "UInt64", "DateTime", "Float64", "DateTime"],
                 query_start_time: query_start_time,
                 query_end_time: query_end_time
               } = result

        assert Sanbase.TestUtils.datetime_close_to(Timex.now(), query_start_time, 2)
        assert Sanbase.TestUtils.datetime_close_to(Timex.now(), query_end_time, 2)
      end)
    end

    test "run dashboard query (without global parameters)", context do
      %{
        dashboard_query_mapping: dashboard_query_mapping,
        user: user,
        query_metadata: query_metadata
      } = context

      Sanbase.Mock.prepare_mock2(&Sanbase.ClickhouseRepo.query/2, {:ok, ch_result_mock()})
      |> Sanbase.Mock.run_with_mocks(fn ->
        {:ok, %{id: query_id} = query} =
          Sanbase.Queries.get_dashboard_query(
            dashboard_query_mapping.dashboard_id,
            dashboard_query_mapping.id,
            user.id
          )

        {:ok, result} =
          Sanbase.Queries.run_query(query, user, query_metadata, store_execution_details: false)

        assert %Sanbase.Queries.Executor.Result{
                 query_id: ^query_id,
                 clickhouse_query_id: "1774C4BC91E05698",
                 summary: %{
                   "read_bytes" => 408_534.0,
                   "read_rows" => 12667.0,
                   "result_bytes" => +0.0,
                   "result_rows" => +0.0,
                   "total_rows_to_read" => 4475.0,
                   "written_bytes" => +0.0,
                   "written_rows" => +0.0
                 },
                 rows: [
                   [
                     1482,
                     1645,
                     ~U[1970-01-01 00:00:00Z],
                     0.045183932486757644,
                     ~U[2023-07-26 13:10:51Z]
                   ],
                   [
                     1482,
                     1647,
                     ~U[1970-01-01 00:00:00Z],
                     -0.13018891098082416,
                     ~U[2023-07-25 20:27:06Z]
                   ]
                 ],
                 compressed_rows: _,
                 columns: ["asset_id", "metric_id", "dt", "value", "computed_at"],
                 column_types: ["UInt64", "UInt64", "DateTime", "Float64", "DateTime"],
                 query_start_time: query_start_time,
                 query_end_time: query_end_time
               } = result

        assert Sanbase.TestUtils.datetime_close_to(Timex.now(), query_start_time, 2)
        assert Sanbase.TestUtils.datetime_close_to(Timex.now(), query_end_time, 2)
      end)
    end

    test "run dashboard query (with global parameters)", context do
      %{
        dashboard_query_mapping: dashboard_query_mapping,
        dashboard: dashboard,
        user: user,
        query_metadata: query_metadata
      } = context

      {:ok, dashboard} =
        Sanbase.Dashboards.add_global_parameter(dashboard.id, user.id,
          key: "slug",
          value: "bitcoin_from_global"
        )

      {:ok, _dashboard} =
        Sanbase.Dashboards.add_global_parameter_override(
          dashboard.id,
          dashboard_query_mapping.id,
          user.id,
          query_parameter_key: "slug",
          dashboard_parameter_key: "slug"
        )

      Sanbase.Mock.prepare_mock2(&Sanbase.ClickhouseRepo.query/2, {:ok, ch_result_mock()})
      |> Sanbase.Mock.run_with_mocks(fn ->
        {:ok, standalone_query} =
          Sanbase.Queries.get_query(dashboard_query_mapping.query_id, user.id)

        # Check that the query when fetched directly has ethereum as slug
        assert standalone_query.sql_query_parameters == %{"slug" => "ethereum", "limit" => 20}

        {:ok, query} =
          Sanbase.Queries.get_dashboard_query(
            dashboard_query_mapping.dashboard_id,
            dashboard_query_mapping.id,
            user.id
          )

        # Check that the query when fetched in the context of a dashboard has bitcoin as slug,
        # because the global parameter has overriden the local one
        assert query.sql_query_parameters == %{"slug" => "bitcoin_from_global", "limit" => 20}

        {:ok, _result} =
          Sanbase.Queries.run_query(query, user, query_metadata, store_execution_details: false)

        assert_called(
          Sanbase.ClickhouseRepo.query(
            :_,
            :meck.is(fn args ->
              # Assert that the query is executed with `ethereum` and not with `bitcoin`
              args == ["bitcoin_from_global", 20]
            end)
          )
        )
      end)
    end
  end

  describe "Caching" do
    test "cache a query", context do
      %{query: query, user: user} = context

      result = query_result_mock()
      {:ok, _cache} = Queries.cache_query_execution(query.id, result, user.id)

      {:ok, cached_result} = Queries.Cache.get(query.id, user.id)

      result2 = Queries.Cache.decode_decompress_result(cached_result.data)

      assert result == result2

      assert result2.rows == [
               [
                 1482,
                 1645,
                 ~U[1970-01-01 00:00:00Z],
                 0.045183932486757644,
                 ~U[2023-07-26 13:10:51Z]
               ],
               [
                 1482,
                 1647,
                 ~U[1970-01-01 00:00:00Z],
                 -0.13018891098082416,
                 ~U[2023-07-25 20:27:06Z]
               ]
             ]

      assert result2.columns == ["asset_id", "metric_id", "dt", "value", "computed_at"]
      assert result2.column_types == ["UInt64", "UInt64", "DateTime", "Float64", "DateTime"]
    end

    test "too big queries are rejected", context do
      %{query: query, user: user} = context

      result = query_result_mock()

      assert {:error, error_msg} =
               Queries.cache_query_execution(query.id, result, user.id,
                 max_query_size_kb_allowed: 0
               )

      assert error_msg =~ "Cannot cache the query because its compressed is"
      assert error_msg =~ "which is over the limit of 0KB"
    end

    test "cannot cache other user private query", context do
      %{user: user, user2: user2} = context
      {:ok, query} = Queries.create_query(%{is_public: false}, user.id)

      assert {:error, error_msg} =
               Queries.cache_query_execution(query.id, query_result_mock(), user2.id)

      assert error_msg =~ "Query does not exist or you don't have access to it"
    end

    test "get cached queries of owner and your own", context do
      %{query: query, user: user, user2: user2} = context

      user3 = insert(:user)
      result = query_result_mock()
      assert {:ok, _} = Queries.cache_query_execution(query.id, result, user.id)
      assert {:ok, _} = Queries.cache_query_execution(query.id, result, user2.id)
      assert {:ok, _} = Queries.cache_query_execution(query.id, result, user3.id)

      # assert that the query is owned by user. we should see this user cache, too
      assert query.user_id == user.id
      {:ok, cached_queries} = Queries.get_cached_query_executions(query.id, user2.id)

      assert length(cached_queries) == 2
      own_cache = Enum.find(cached_queries, &(&1.user_id == user2.id))
      owner_cache = Enum.find(cached_queries, &(&1.user_id == user.id))

      own_cache_result = Queries.Cache.decode_decompress_result(own_cache.data)
      owner_cache_result = Queries.Cache.decode_decompress_result(owner_cache.data)

      # The decoded result is the same as the stored one
      assert own_cache_result == query_result_mock()
      assert owner_cache_result == query_result_mock()

      # Check insertion time
      assert Sanbase.TestUtils.datetime_close_to(own_cache.inserted_at, DateTime.utc_now(),
               seconds: 2
             )

      assert Sanbase.TestUtils.datetime_close_to(owner_cache.inserted_at, DateTime.utc_now(),
               seconds: 2
             )

      # Check owner
      assert own_cache.user_id == user2.id
      assert owner_cache.user_id == user.id

      # Check if hashes match. They should as the query has not changed
      assert own_cache.is_query_hash_matching == true
      assert owner_cache.is_query_hash_matching == true
    end

    test "is_query_hash_matching changes if query is updated", context do
      %{query: query, user: user} = context

      assert {:ok, _} = Queries.cache_query_execution(query.id, query_result_mock(), user.id)

      # If the query is not changed, the hashes are matching
      assert {:ok, [cache]} = Queries.get_cached_query_executions(query.id, user.id)
      assert cache.is_query_hash_matching == true

      assert {:ok, _} =
               Queries.update_query(
                 query.id,
                 %{sql_query_text: "SELECT * FROM github_v2 LIMIT 22"},
                 user.id
               )

      # If the query is not changed, the hashes are matching
      assert {:ok, [cache]} = Queries.get_cached_query_executions(query.id, user.id)
      assert cache.is_query_hash_matching == false
    end
  end

  describe "Code Parameters" do
    test "resolve code parameters", context do
      {:ok, query} =
        Queries.create_query(
          %{
            sql_query_text:
              "SELECT address FROM balances WHERE address IN ({{addresses}}) LIMIT {{limit}}",
            sql_query_parameters: %{
              "addresses" => ~s|{% load("/users/32/my_addresses") %}|,
              "threshold" => ~s|{% pow(10, 5) %}|,
              "limit" => 20
            }
          },
          context.user.id
        )

      addresses =
        [
          "0xe2f2a5C287993345a840db3B0845fbc70f5935a5",
          "0x5AEDA56215b167893e80B4fE645BA6d5Bab767DE",
          "0x2f0b23f53734252bda2277357e97e1517d6b042a"
        ]

      Sanbase.Mock.prepare_mock2(&Sanbase.Queries.ExternalFiles.get/1, {:ok, addresses})
      |> Sanbase.Mock.run_with_mocks(fn ->
        {:ok, query} = Queries.resolve_code_parameters(query, context.user.id)

        assert query.sql_query_parameters == %{
                 "addresses" => addresses,
                 "threshold" => 100_000,
                 "limit" => 20
               }
      end)
    end
  end

  # MOCKS

  defp query_result_mock() do
    %Sanbase.Queries.Executor.Result{
      query_id: 1193,
      clickhouse_query_id: "1774C4BC91E05698",
      summary: %{
        "read_bytes" => 408_534.0,
        "read_rows" => 12667.0,
        "result_bytes" => 0.0,
        "result_rows" => 0.0,
        "total_rows_to_read" => 4475.0,
        "written_bytes" => 0.0,
        "written_rows" => 0.0
      },
      rows: [
        [1482, 1645, ~U[1970-01-01 00:00:00Z], 0.045183932486757644, ~U[2023-07-26 13:10:51Z]],
        [1482, 1647, ~U[1970-01-01 00:00:00Z], -0.13018891098082416, ~U[2023-07-25 20:27:06Z]]
      ],
      compressed_rows: nil,
      columns: ["asset_id", "metric_id", "dt", "value", "computed_at"],
      column_types: ["UInt64", "UInt64", "DateTime", "Float64", "DateTime"],
      query_start_time: ~U[2024-02-29 15:36:55.493Z],
      query_end_time: ~U[2024-02-29 15:36:55.498Z]
    }
  end

  defp ch_result_mock() do
    %Clickhousex.Result{
      query_id: "1774C4BC91E05698",
      summary: %{
        "read_bytes" => "408534",
        "read_rows" => "12667",
        "result_bytes" => "0",
        "result_rows" => "0",
        "total_rows_to_read" => "4475",
        "written_bytes" => "0",
        "written_rows" => "0"
      },
      command: :selected,
      columns: ["asset_id", "metric_id", "dt", "value", "computed_at"],
      column_types: ["UInt64", "UInt64", "DateTime", "Float64", "DateTime"],
      rows: [
        [1482, 1645, ~N[1970-01-01 00:00:00], 0.045183932486757644, ~N[2023-07-26 13:10:51]],
        [1482, 1647, ~N[1970-01-01 00:00:00], -0.13018891098082416, ~N[2023-07-25 20:27:06]]
      ],
      num_rows: 2
    }
  end

  defp execution_details_mock() do
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
