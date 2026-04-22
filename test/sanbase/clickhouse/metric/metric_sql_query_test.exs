defmodule Sanbase.Clickhouse.MetricAdapter.SqlQueryTest do
  use Sanbase.DataCase, async: false

  alias Sanbase.Clickhouse.Query
  alias Sanbase.Clickhouse.MetricAdapter.SqlQuery

  describe "available_metrics_for_selector_query/2" do
    test "uses default 14 days lookback when opt not provided" do
      query = SqlQuery.available_metrics_for_selector_query(%{slug: "bitcoin"})

      assert {:ok, %{sql: sql, args: args}} = Query.get_sql_args(query)
      assert sql =~ ~r/INTERVAL \{lookback_days:\w+\} DAY/
      assert args["lookback_days"] == 14
      assert args["selector"] == "bitcoin"
    end

    test "uses default when lookback_days opt is nil" do
      query =
        SqlQuery.available_metrics_for_selector_query(%{slug: "bitcoin"}, lookback_days: nil)

      assert {:ok, %{args: args}} = Query.get_sql_args(query)
      assert args["lookback_days"] == 14
    end

    test "uses provided lookback_days when set" do
      query =
        SqlQuery.available_metrics_for_selector_query(%{slug: "bitcoin"}, lookback_days: 365)

      assert {:ok, %{sql: sql, args: args}} = Query.get_sql_args(query)
      assert sql =~ ~r/INTERVAL \{lookback_days:\w+\} DAY/
      assert args["lookback_days"] == 365
    end

    test "very large lookback_days is passed through verbatim (no cap)" do
      query =
        SqlQuery.available_metrics_for_selector_query(%{slug: "bitcoin"}, lookback_days: 100_000)

      assert {:ok, %{args: args}} = Query.get_sql_args(query)
      assert args["lookback_days"] == 100_000
    end
  end

  describe "available_slugs_for_metric_query/2" do
    test "uses default 14 days lookback when opt not provided" do
      query = SqlQuery.available_slugs_for_metric_query("daily_active_addresses", [])

      assert query.sql =~ ~r/INTERVAL \{\{lookback_days\}\} DAY/
      assert query.parameters.lookback_days == 14
    end

    test "uses default when lookback_days opt is nil" do
      query =
        SqlQuery.available_slugs_for_metric_query("daily_active_addresses", lookback_days: nil)

      assert query.parameters.lookback_days == 14
    end

    test "uses provided lookback_days when set" do
      query =
        SqlQuery.available_slugs_for_metric_query("daily_active_addresses", lookback_days: 90)

      assert query.sql =~ ~r/INTERVAL \{\{lookback_days\}\} DAY/
      assert query.parameters.lookback_days == 90
    end
  end
end
