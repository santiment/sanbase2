defmodule Sanbase.Clickhouse.QueryTest do
  # Not async — these tests manipulate Logger.metadata that production code
  # also consults to apply privacy SETTINGS.
  use Sanbase.DataCase, async: false

  import Sanbase.Factory

  alias Sanbase.Clickhouse.Query
  alias Sanbase.RequestContext

  setup do
    Logger.reset_metadata([])
    on_exit(fn -> Logger.reset_metadata([]) end)

    protected = insert(:user)
    unprotected = insert(:user)
    Sanbase.PrivacyCacheSeed.seed!([protected.id])

    {:ok, protected: protected, unprotected: unprotected}
  end

  test "interpolate replaces named placeholders from params map" do
    query = "SELECT {limit:UInt8}, {slug:String}, {labels:Array(String)}"

    assert Query.interpolate(query, %{
             "limit" => 3,
             "slug" => "bitcoin",
             "labels" => ["exchange", "whale"]
           }) == "SELECT 3, 'bitcoin', ['exchange','whale']"
  end

  test "interpolate still supports positional placeholders" do
    query = "SELECT {$0:Int32}, {$1:String}"

    assert Query.interpolate(query, [42, "ethereum"]) == "SELECT 42, 'ethereum'"
  end

  test "interpolate replaces typed placeholders with values" do
    sql = "SELECT {$0:Int32}, {$1:String}, {$2:Array(Int32)}"

    assert Query.interpolate(sql, [42, "bitcoin", [1, 2]]) == "SELECT 42, 'bitcoin', [1,2]"
  end

  describe "get_sql_args ambient context (Logger.metadata fallback)" do
    test "protected user ctx in Logger.metadata triggers log_queries=0 and strips stacktrace / graphql_request_log_id",
         %{protected: user} do
      Logger.metadata(
        request_context: %RequestContext{
          origin: :graphql,
          user_id: user.id,
          activity_traces_hidden: true
        }
      )

      query =
        Query.new("SELECT 1", %{},
          log_comment: %{
            stacktrace: ["a", "b"],
            graphql_request_log_id: 42,
            keep_me: "ok"
          }
        )

      {:ok, %{sql: sql}} = Query.get_sql_args(query)

      assert sql =~ "log_queries=0"
      assert sql =~ "log_comment="
      assert sql =~ "\"keep_me\":\"ok\""
      assert sql =~ "\"user_id\":#{user.id}"
      refute sql =~ "stacktrace"
      refute sql =~ "graphql_request_log_id"
    end

    test "non-protected ctx in Logger.metadata: keeps log_comment as-is, no log_queries=0",
         %{unprotected: user} do
      Logger.metadata(
        request_context: %RequestContext{
          origin: :graphql,
          user_id: user.id,
          activity_traces_hidden: false
        }
      )

      query =
        Query.new("SELECT 1", %{}, log_comment: %{stacktrace: ["a"], graphql_request_log_id: 7})

      {:ok, %{sql: sql}} = Query.get_sql_args(query)

      refute sql =~ "log_queries=0"
      assert sql =~ "\"user_id\":#{user.id}"
      assert sql =~ "stacktrace"
      assert sql =~ "graphql_request_log_id"
    end

    test "no ambient context: user_id=0 in log_comment, no log_queries=0" do
      query = Query.new("SELECT 1", %{}, log_comment: %{some: "thing"})

      {:ok, %{sql: sql}} = Query.get_sql_args(query)

      refute sql =~ "log_queries=0"
      assert sql =~ "\"user_id\":0"
    end
  end

  describe "log_comment SQL literal escaping" do
    # `graphql_request_log_id` carries the client's `x-request-id` header.
    test "a quote in the log_comment cannot close the literal and add SETTINGS" do
      injected = "aaaaaaaaaaaaaaaaaaaa',readonly=0,max_execution_time=999999 --"

      query = Query.new("SELECT 1", %{}, log_comment: %{graphql_request_log_id: injected})

      {:ok, %{sql: sql}} = Query.get_sql_args(query)

      # Carried verbatim, but with the quote escaped — inert data, not SQL.
      assert sql =~ "\\',readonly=0"

      # The literal is closed exactly once, at the very end.
      [_before, after_open] = String.split(sql, " log_comment='", parts: 2)
      assert unescaped_quote_positions(after_open) == [String.length(after_open) - 1]
    end

    test "a backslash in the log_comment is escaped before the quotes are" do
      query = Query.new("SELECT 1", %{}, log_comment: %{stacktrace: "a\\'b"})

      {:ok, %{sql: sql}} = Query.get_sql_args(query)

      [_before, after_open] = String.split(sql, " log_comment='", parts: 2)
      assert unescaped_quote_positions(after_open) == [String.length(after_open) - 1]
    end
  end

  # Indices of the `'` characters that ClickHouse would read as terminating a
  # string literal — those preceded by an even number of backslashes.
  defp unescaped_quote_positions(str) do
    str
    |> String.graphemes()
    |> Enum.with_index()
    |> Enum.reduce({[], 0}, fn
      {"\\", _i}, {acc, backslashes} -> {acc, backslashes + 1}
      {"'", i}, {acc, backslashes} when rem(backslashes, 2) == 0 -> {[i | acc], 0}
      {_char, _i}, {acc, _backslashes} -> {acc, 0}
    end)
    |> then(fn {positions, _} -> Enum.reverse(positions) end)
  end

  describe "get_sql_args with explicit RequestContext (preferred)" do
    test "protected explicit ctx wins even when Logger.metadata says non-protected", %{
      protected: protected,
      unprotected: unprotected
    } do
      Logger.metadata(
        request_context: %RequestContext{
          origin: :graphql,
          user_id: unprotected.id,
          activity_traces_hidden: false
        }
      )

      ctx = %RequestContext{
        origin: :graphql,
        user_id: protected.id,
        activity_traces_hidden: true
      }

      query =
        Query.new("SELECT 1", %{},
          context: ctx,
          log_comment: %{stacktrace: ["a"], graphql_request_log_id: 1, keep_me: "ok"}
        )

      {:ok, %{sql: sql}} = Query.get_sql_args(query)

      assert sql =~ "log_queries=0"
      assert sql =~ "\"user_id\":#{protected.id}"
      assert sql =~ "\"keep_me\":\"ok\""
      refute sql =~ "stacktrace"
      refute sql =~ "graphql_request_log_id"
    end

    test "non-protected explicit ctx wins even when Logger.metadata says protected", %{
      protected: protected,
      unprotected: unprotected
    } do
      Logger.metadata(
        request_context: %RequestContext{
          origin: :graphql,
          user_id: protected.id,
          activity_traces_hidden: true
        }
      )

      ctx = %RequestContext{
        origin: :graphql,
        user_id: unprotected.id,
        activity_traces_hidden: false
      }

      query =
        Query.new("SELECT 1", %{},
          context: ctx,
          log_comment: %{stacktrace: ["a"], graphql_request_log_id: 1}
        )

      {:ok, %{sql: sql}} = Query.get_sql_args(query)

      refute sql =~ "log_queries=0"
      assert sql =~ "\"user_id\":#{unprotected.id}"
      assert sql =~ "stacktrace"
    end

    test "anonymous explicit ctx (user_id nil) → user_id=0, no log_queries=0" do
      query =
        Query.new("SELECT 1", %{},
          context: RequestContext.anonymous(:graphql),
          log_comment: %{some: "thing"}
        )

      {:ok, %{sql: sql}} = Query.get_sql_args(query)

      refute sql =~ "log_queries=0"
      assert sql =~ "\"user_id\":0"
    end
  end
end
