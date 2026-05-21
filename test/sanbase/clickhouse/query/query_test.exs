defmodule Sanbase.Clickhouse.QueryTest do
  # Not async — these tests manipulate the process-dictionary user-id key
  # that production code also consults to apply privacy SETTINGS.
  use ExUnit.Case, async: false

  alias Sanbase.Accounts
  alias Sanbase.Clickhouse.Query
  alias Sanbase.RequestContext

  @current_user_id_key :__graphql_query_current_user_id__

  setup do
    Process.delete(@current_user_id_key)
    on_exit(fn -> Process.delete(@current_user_id_key) end)
    :ok
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

  describe "get_sql_args privacy settings" do
    test "appends log_queries=0 and strips stacktrace / graphql_request_log_id for protected users" do
      protected_id = Accounts.privacy_protected_user_ids() |> Enum.at(0)
      Process.put(@current_user_id_key, protected_id)

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
      assert sql =~ "\"user_id\":#{protected_id}"
      refute sql =~ "stacktrace"
      refute sql =~ "graphql_request_log_id"
    end

    test "non-protected user: keeps log_comment as-is, no log_queries=0" do
      protected = Accounts.privacy_protected_user_ids()
      outside = Enum.find(1_000..2_000, fn id -> not MapSet.member?(protected, id) end)
      Process.put(@current_user_id_key, outside)

      query =
        Query.new("SELECT 1", %{}, log_comment: %{stacktrace: ["a"], graphql_request_log_id: 7})

      {:ok, %{sql: sql}} = Query.get_sql_args(query)

      refute sql =~ "log_queries=0"
      assert sql =~ "\"user_id\":#{outside}"
      assert sql =~ "stacktrace"
      assert sql =~ "graphql_request_log_id"
    end

    test "anonymous user: user_id=0 in log_comment, no log_queries=0" do
      query = Query.new("SELECT 1", %{}, log_comment: %{some: "thing"})

      {:ok, %{sql: sql}} = Query.get_sql_args(query)

      refute sql =~ "log_queries=0"
      assert sql =~ "\"user_id\":0"
    end
  end

  describe "get_sql_args with explicit RequestContext" do
    test "protected ctx wins even when process-dict says non-protected" do
      # Process dict holds a non-protected user; explicit ctx says protected.
      # The struct must take precedence — no consultation of the process
      # dict on this code path.
      Process.put(@current_user_id_key, 999_999)
      protected_id = Accounts.privacy_protected_user_ids() |> Enum.at(0)

      ctx = %RequestContext{
        origin: :graphql,
        user_id: protected_id,
        privacy_protected: true
      }

      query =
        Query.new("SELECT 1", %{},
          context: ctx,
          log_comment: %{stacktrace: ["a"], graphql_request_log_id: 1, keep_me: "ok"}
        )

      {:ok, %{sql: sql}} = Query.get_sql_args(query)

      assert sql =~ "log_queries=0"
      assert sql =~ "\"user_id\":#{protected_id}"
      assert sql =~ "\"keep_me\":\"ok\""
      refute sql =~ "stacktrace"
      refute sql =~ "graphql_request_log_id"
    end

    test "non-protected ctx wins even when process-dict says protected" do
      # Process dict holds a protected user; explicit ctx says safe. The
      # struct must take precedence — this is the failure mode the
      # migration exists to fix (stale Cowboy worker state).
      protected_id = Accounts.privacy_protected_user_ids() |> Enum.at(0)
      Process.put(@current_user_id_key, protected_id)

      ctx = %RequestContext{
        origin: :graphql,
        user_id: 42_000,
        privacy_protected: false
      }

      query =
        Query.new("SELECT 1", %{},
          context: ctx,
          log_comment: %{stacktrace: ["a"], graphql_request_log_id: 1}
        )

      {:ok, %{sql: sql}} = Query.get_sql_args(query)

      refute sql =~ "log_queries=0"
      assert sql =~ "\"user_id\":42000"
      assert sql =~ "stacktrace"
    end

    test "anonymous ctx (user_id nil) → user_id=0, no log_queries=0" do
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
