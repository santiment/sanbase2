defmodule Sanbase.Clickhouse.MetricAdapter.SqlQueryTest do
  use Sanbase.DataCase, async: true

  alias Sanbase.Clickhouse.Query
  alias Sanbase.Clickhouse.MetricAdapter.SqlQuery

  describe "available_metrics_for_selector_query/2" do
    test "uses default 14 days lookback when opt not provided" do
      query = SqlQuery.available_metrics_for_selector_query(%{slug: "bitcoin"})
      {:ok, %{sql: sql, args: args}} = Query.get_sql_args(query)

      assert sql =~ ~r/INTERVAL \{lookback_days:\w+\} DAY/
      assert args["lookback_days"] == 14
      assert args["selector"] == "bitcoin"
    end

    test "uses default when lookback_days opt is nil" do
      query =
        SqlQuery.available_metrics_for_selector_query(%{slug: "bitcoin"}, lookback_days: nil)

      {:ok, %{args: args}} = Query.get_sql_args(query)
      assert args["lookback_days"] == 14
    end

    test "uses provided lookback_days when set" do
      query =
        SqlQuery.available_metrics_for_selector_query(%{slug: "bitcoin"}, lookback_days: 365)

      {:ok, %{sql: sql, args: args}} = Query.get_sql_args(query)
      assert sql =~ ~r/INTERVAL \{lookback_days:\w+\} DAY/
      assert args["lookback_days"] == 365
    end
  end

  describe "available_slugs_for_metric_query/2" do
    test "uses default 14 days lookback when opt not provided" do
      query = SqlQuery.available_slugs_for_metric_query("daily_active_addresses", [])
      {:ok, %{sql: sql, args: args}} = Query.get_sql_args(query)

      assert sql =~ ~r/INTERVAL \{lookback_days:\w+\} DAY/
      assert args["lookback_days"] == 14
    end

    test "uses default when lookback_days opt is nil" do
      query =
        SqlQuery.available_slugs_for_metric_query("daily_active_addresses", lookback_days: nil)

      {:ok, %{args: args}} = Query.get_sql_args(query)
      assert args["lookback_days"] == 14
    end

    test "uses provided lookback_days when set" do
      query =
        SqlQuery.available_slugs_for_metric_query("daily_active_addresses", lookback_days: 90)

      {:ok, %{sql: sql, args: args}} = Query.get_sql_args(query)
      assert sql =~ ~r/INTERVAL \{lookback_days:\w+\} DAY/
      assert args["lookback_days"] == 90
    end
  end
end
