defmodule Sanbase.MCP.Dev.ToolsTest do
  use Sanbase.DataCase, async: false

  import Mock
  import Sanbase.Factory

  alias Anubis.Server.Frame
  alias Anubis.Server.Response
  alias Sanbase.MCP.Dev

  @moduletag capture_log: true

  setup do
    user = insert(:user, email: "dev@santiment.net")
    %{user: user, frame: Frame.new(%{current_user: user})}
  end

  defp call(tool, params, frame) do
    {:reply, %Response{} = response, _frame} = tool.execute(params, frame)
    protocol = Response.to_protocol(response)
    [%{"text" => text}] = protocol["content"]

    if protocol["isError"], do: {:error, text}, else: {:ok, Jason.decode!(text)}
  end

  defp ch_result(columns, rows) do
    %{
      query_id: "ch-query-id",
      summary: %{"read_rows" => "10", "read_bytes" => "100"},
      command: :selected,
      columns: columns,
      column_types: Enum.map(columns, fn _ -> "String" end),
      rows: rows,
      num_rows: length(rows)
    }
  end

  # Records the dynamic repo and the SQL of every ClickHouse query.
  defp with_ch(results, fun) do
    test_pid = self()
    agent = start_supervised!({Agent, fn -> results end})

    Sanbase.Mock.prepare_mock(Sanbase.ClickhouseRepo, :query, fn sql, args, _opts ->
      send(test_pid, {:ch_query, Process.get(:queries_dynamic_repo), sql, args})
      Agent.get_and_update(agent, fn [result | rest] -> {result, rest} end)
    end)
    |> Sanbase.Mock.run_with_mocks(fun)
  end

  describe "execute_sql" do
    # `execute_sql` stores its execution details, which runs another ClickHouse query.
    setup do
      Application.put_env(:__sanbase_queries__, :__store_execution_details__, false)

      on_exit(fn ->
        Application.delete_env(:__sanbase_queries__, :__store_execution_details__)
      end)
    end

    test "runs through Queries with BUSINESS_MAX access and truncates rows", %{frame: frame} do
      rows = for i <- 1..3, do: [i, "row #{i}", {i, "tuple"}]

      with_ch([{:ok, ch_result(["n", "name", "pair"], rows)}], fn ->
        assert {:ok, result} =
                 call(
                   Dev.ExecuteSqlTool,
                   %{
                     sql: "SELECT n FROM t WHERE x = {{x}}",
                     parameters: %{"x" => "a"},
                     max_rows: 2
                   },
                   frame
                 )

        assert %{
                 "columns" => ["n", "name", "pair"],
                 "rows" => [[1, "row 1", [1, "tuple"]], [2, "row 2", [2, "tuple"]]],
                 "row_count" => 2,
                 "truncated" => true,
                 "clickhouse_query_id" => "ch-query-id"
               } = result

        assert_receive {:ch_query, Sanbase.ClickhouseRepo.BusinessMaxUser, sql, args}
        assert sql =~ "__sanbase_user_id_running_the_query__ #{frame.assigns.current_user.id}"

        assert sql =~ "max_result_rows=3"
        assert sql =~ "result_overflow_mode='break'"
        assert sql =~ "max_execution_time=60"
        assert args |> Map.values() |> Enum.member?("a")
      end)

      refute Process.get(:queries_dynamic_repo)
      assert Sanbase.ClickhouseRepo.get_dynamic_repo() == Sanbase.ClickhouseRepo
    end

    test "reports truncation when the byte limit stopped the query", %{frame: frame} do
      result = %{ch_result(["n"], [[1]]) | summary: %{"result_bytes" => "40000000"}}

      with_ch([{:ok, result}], fn ->
        assert {:ok, %{"row_count" => 1, "truncated" => true}} =
                 call(Dev.ExecuteSqlTool, %{sql: "SELECT n FROM t"}, frame)
      end)
    end

    test "returns ClickHouse errors as tool errors", %{frame: frame} do
      with_ch([{:error, "Table default.nope does not exist"}], fn ->
        assert {:error, message} = call(Dev.ExecuteSqlTool, %{sql: "SELECT * FROM nope"}, frame)
        assert message =~ "does not exist"
      end)
    end
  end

  describe "list_tables and describe_tables" do
    test "list_tables filters by name", %{frame: frame} do
      rows = [["intraday_metrics", "Distributed", "asset_id, metric_id, dt", "", 10, ""]]
      columns = ~w(name engine sorting_key partition_key total_rows comment)

      with_ch([{:ok, ch_result(columns, rows)}], fn ->
        assert {:ok, %{"count" => 1, "tables" => [table]}} =
                 call(Dev.ListTablesTool, %{name_filter: " intraday "}, frame)

        assert table["name"] == "intraday_metrics"
        assert_receive {:ch_query, Sanbase.ClickhouseRepo.BusinessMaxUser, sql, args}
        assert sql =~ "system.tables"
        assert args |> Map.values() |> Enum.member?("intraday")
      end)
    end

    test "describe_tables groups the columns per table and reports missing ones",
         %{frame: frame} do
      tables_columns = ~w(name engine sorting_key partition_key primary_key total_rows comment)
      tables_rows = [["daily_metrics_v2", "Distributed", "asset_id, dt", "", "asset_id", 5, ""]]

      columns_columns =
        ~w(table name type default_kind default_expression comment is_in_partition_key is_in_sorting_key is_in_primary_key)

      columns_rows = [
        ["daily_metrics_v2", "asset_id", "UInt64", "", "", "", 0, 1, 1],
        ["daily_metrics_v2", "value", "Float64", "", "", "The value", 0, 0, 0]
      ]

      with_ch(
        [
          {:ok, ch_result(tables_columns, tables_rows)},
          {:ok, ch_result(columns_columns, columns_rows)}
        ],
        fn ->
          assert {:ok, %{"tables" => [table], "not_found" => ["missing"]}} =
                   call(Dev.DescribeTablesTool, %{tables: ["daily_metrics_v2", "missing"]}, frame)

          assert [
                   %{"name" => "asset_id", "in_sorting_key" => true, "comment" => nil},
                   %{"name" => "value", "in_sorting_key" => false, "comment" => "The value"}
                 ] = table["columns"]
        end
      )
    end

    test "describe_tables rejects an empty list", %{frame: frame} do
      assert {:error, message} = call(Dev.DescribeTablesTool, %{tables: [" "]}, frame)
      assert message =~ "[permanent]"
    end

    test "describe_tables rejects a null table name", %{frame: frame} do
      assert {:error, message} =
               call(Dev.DescribeTablesTool, %{tables: ["daily_metrics_v2", nil]}, frame)

      assert message =~ "[permanent]"
    end
  end

  describe "social_messages" do
    defp hub_response(total, messages) do
      {:ok,
       %Req.Response{
         status: 200,
         body: %{"data" => %{"stats" => %{"total_matching" => total}, "messages" => messages}}
       }}
    end

    test "queries by slug and passes the options", %{frame: frame} do
      test_pid = self()

      with_mock Req,
        post: fn url, opts ->
          send(test_pid, {:post, url, opts[:json]})
          hub_response(2, [%{"text" => "gm", "stratum" => "random"}])
        end do
        assert {:ok, %{"stats" => %{"total_matching" => 2}, "messages" => [_]}} =
                 call(
                   Dev.SocialMessagesTool,
                   %{asset: "Bitcoin", from: "utc_now-7d", sources: ["Reddit", "telegram"]},
                   frame
                 )

        assert_receive {:post, url, body}
        assert url =~ "/sample_documents"

        assert body == %{
                 slug: "bitcoin",
                 from_timestamp: "now-7d",
                 sources: "reddit,telegram",
                 max_words: 10_000
               }
      end
    end

    test "falls back to a free-text search when the slug matches nothing", %{frame: frame} do
      with_mock Req,
        post: fn _url, opts ->
          if opts[:json][:slug],
            do: hub_response(0, []),
            else: hub_response(1, [%{"text" => "x"}])
        end do
        assert {:ok, %{"stats" => stats}} = call(Dev.SocialMessagesTool, %{asset: "zzz"}, frame)
        assert stats["query_mode"] == "search_text"
      end
    end

    test "says so when there is no data", %{frame: frame} do
      with_mock Req, post: fn _url, _opts -> hub_response(0, []) end do
        assert {:ok, %{"note" => note, "messages" => []}} =
                 call(Dev.SocialMessagesTool, %{asset: "zzz"}, frame)

        assert note =~ "No social messages"
        assert note =~ "project slug and as free text"
      end
    end

    test "says a non-slug asset was searched as free text only", %{frame: frame} do
      test_pid = self()

      with_mock Req,
        post: fn _url, opts ->
          send(test_pid, {:json, opts[:json]})
          hub_response(0, [])
        end do
        assert {:ok, %{"note" => note}} = call(Dev.SocialMessagesTool, %{asset: "$PEPE"}, frame)

        assert note =~ "free text only"
        refute note =~ "project slug and as free text"
        assert_receive {:json, %{search_text: "$PEPE"}}
        refute_receive {:json, _}
      end
    end

    test "rejects a null source without calling metrics-hub", %{frame: frame} do
      with_mock Req, post: fn _url, _opts -> raise "must not be called" end do
        assert {:error, message} =
                 call(
                   Dev.SocialMessagesTool,
                   %{asset: "bitcoin", sources: ["reddit", nil]},
                   frame
                 )

        assert message =~ "[permanent]"
      end
    end

    test "rejects unknown sources without calling metrics-hub", %{frame: frame} do
      with_mock Req, post: fn _url, _opts -> raise "must not be called" end do
        assert {:error, message} =
                 call(Dev.SocialMessagesTool, %{asset: "bitcoin", sources: ["myspace"]}, frame)

        assert message =~ "[permanent]"
        assert message =~ "myspace"
      end
    end

    test "tags gateway failures as transient", %{frame: frame} do
      with_mock Req,
        post: fn _url, _opts ->
          {:ok, %Req.Response{status: 503, body: %{"error" => "boom", "trace" => "..."}}}
        end do
        assert {:error, message} = call(Dev.SocialMessagesTool, %{asset: "search words"}, frame)
        assert message =~ "[transient]"
        assert message =~ "boom"
        refute message =~ "trace"
      end
    end

    test "leaves metrics-hub 500s untagged", %{frame: frame} do
      with_mock Req,
        post: fn _url, _opts ->
          {:ok,
           %Req.Response{
             status: 500,
             body: %{"error" => "module metricshub has no attribute tweets_by_author"}
           }}
        end do
        assert {:error, message} = call(Dev.TweetsByAuthorTool, %{screen_name: "x_user"}, frame)
        assert message =~ "no attribute"
        refute message =~ "[transient]"
      end
    end
  end

  describe "social_messages errors" do
    # metrics-hub answers 400 for every exception, so the cause decides permanence.
    test "leaves metrics-hub 400s untagged", %{frame: frame} do
      with_mock Req,
        post: fn _url, _opts ->
          {:ok,
           %Req.Response{status: 400, body: %{"error" => "ConnectionTimeout", "trace" => "..."}}}
        end do
        assert {:error, message} = call(Dev.SocialMessagesTool, %{asset: "bitcoin"}, frame)
        assert message =~ "ConnectionTimeout"
        refute message =~ "[permanent]"
        refute message =~ "[transient]"
      end
    end
  end

  describe "tweets_by_author" do
    defp tweets_response(stats, posts) do
      {:ok,
       %Req.Response{
         status: 200,
         body: %{
           "data" => %{
             "account" => %{"screen_name" => "SantimentData", "author_id" => "123"},
             "stats" => stats,
             "posts" => posts
           }
         }
       }}
    end

    test "normalizes the handle and passes the options", %{frame: frame} do
      test_pid = self()

      with_mock Req,
        post: fn url, opts ->
          send(test_pid, {:post, url, opts[:json]})

          tweets_response(%{"total_matching" => 1, "truncated" => false}, [
            %{"id" => "1", "text" => "gm"}
          ])
        end do
        assert {:ok, %{"posts" => [%{"text" => "gm"}], "account" => _} = result} =
                 call(
                   Dev.TweetsByAuthorTool,
                   %{
                     screen_name: "https://x.com/SantimentData/status/1",
                     from: "utc_now-30d",
                     include_retweets: false,
                     sources: ["twitter_crypto"]
                   },
                   frame
                 )

        refute Map.has_key?(result, "note")
        assert_receive {:post, url, body}
        assert url =~ "/tweets_by_author"

        assert body == %{
                 screen_name: "SantimentData",
                 from_timestamp: "now-30d",
                 include_retweets: false,
                 sources: "twitter_crypto",
                 max_posts: 200
               }
      end
    end

    test "reads the account from the different x.com link shapes", %{frame: frame} do
      test_pid = self()

      cases = [
        {"https://x.com/i/user/783214", %{author_id: "783214"}},
        {"twitter.com/intent/user?user_id=42", %{author_id: "42"}},
        {"https://twitter.com/intent/follow?screen_name=foo_bar", %{screen_name: "foo_bar"}},
        {"x.com/SantimentData?lang=en", %{screen_name: "SantimentData"}},
        {"@SantimentData", %{screen_name: "SantimentData"}}
      ]

      with_mock Req,
        post: fn _url, opts ->
          send(test_pid, {:json, opts[:json]})
          tweets_response(%{"total_matching" => 0}, [])
        end do
        for {input, expected} <- cases do
          call(Dev.TweetsByAuthorTool, %{screen_name: input}, frame)
          assert_receive {:json, body}
          assert Map.take(body, [:screen_name, :author_id]) == expected, inspect(input)
        end
      end
    end

    test "rejects x.com links that name no account", %{frame: frame} do
      with_mock Req, post: fn _url, _opts -> raise "must not be called" end do
        for input <- ["https://x.com/i/web/status/123", "x.com/search?q=btc", "https://x.com/"] do
          assert {:error, message} = call(Dev.TweetsByAuthorTool, %{screen_name: input}, frame)
          assert message =~ "[permanent]", inspect(input)
        end
      end
    end

    test "rejects a null source", %{frame: frame} do
      with_mock Req, post: fn _url, _opts -> raise "must not be called" end do
        assert {:error, message} =
                 call(Dev.TweetsByAuthorTool, %{screen_name: "foo", sources: [nil]}, frame)

        assert message =~ "[permanent]"
      end
    end

    test "passes author_id and caps max_posts", %{frame: frame} do
      test_pid = self()

      with_mock Req,
        post: fn _url, opts ->
          send(test_pid, {:json, opts[:json]})
          tweets_response(%{"total_matching" => 0}, [])
        end do
        call(Dev.TweetsByAuthorTool, %{author_id: "123", max_posts: 1_000_000}, frame)
        assert_receive {:json, %{author_id: "123", max_posts: 10_000} = body}
        refute Map.has_key?(body, :screen_name)
      end
    end

    test "explains an empty window", %{frame: frame} do
      responses = [
        {%{"account_indexed" => false, "latest_indexed_post" => nil}, "does not index"},
        {%{"account_indexed" => true, "latest_indexed_post" => "2026-05-01T10:00:00"},
         "2026-05-01T10:00:00"}
      ]

      for {stats, expected} <- responses do
        with_mock Req, post: fn _url, _opts -> tweets_response(stats, []) end do
          assert {:ok, %{"note" => note}} =
                   call(Dev.TweetsByAuthorTool, %{screen_name: "nobody"}, frame)

          assert note =~ expected
        end
      end
    end

    test "rejects bad input without calling metrics-hub", %{frame: frame} do
      with_mock Req, post: fn _url, _opts -> raise "must not be called" end do
        for params <- [
              %{},
              %{screen_name: "has space"},
              %{screen_name: "way_too_long_handle_name"},
              %{author_id: "santimentdata"},
              %{screen_name: "santimentdata", sources: ["reddit"]}
            ] do
          assert {:error, "[permanent] " <> _} = call(Dev.TweetsByAuthorTool, params, frame)
        end
      end
    end
  end

  describe "log_tool_call/3" do
    test "redacts detail when activity traces are hidden and escapes newlines otherwise", %{
      user: user
    } do
      on_exit(fn -> Logger.reset_metadata([]) end)

      Sanbase.RequestContext.put_logger_metadata(%Sanbase.RequestContext{
        origin: :mcp,
        user_id: user.id,
        activity_traces_hidden: true
      })

      hidden_log =
        ExUnit.CaptureLog.capture_log(fn ->
          Dev.Server.log_tool_call(user, "social_messages", "secret-coin")
        end)

      assert hidden_log =~ "[MCP Dev] User #{user.id} social_messages"
      refute hidden_log =~ "secret-coin"

      Sanbase.RequestContext.put_logger_metadata(%Sanbase.RequestContext{
        origin: :mcp,
        user_id: user.id,
        activity_traces_hidden: false
      })

      visible_log =
        ExUnit.CaptureLog.capture_log(fn ->
          Dev.Server.log_tool_call(user, "social_messages", "btc\nforged")
        end)

      assert visible_log =~ ~s("btc\\nforged")
    end
  end
end
