defmodule Sanbase.Clickhouse.MetricAdapter.SqlQueryTest do
  use Sanbase.DataCase, async: true

  alias Sanbase.Clickhouse.Query
  alias Sanbase.Clickhouse.MetricAdapter.SqlQuery
  alias Sanbase.Clickhouse.MetricAdapter.Registry

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

  describe "last_datetime_computed_at_query/3" do
    test "filters on version 1.0 when no version is given" do
      query =
        SqlQuery.last_datetime_computed_at_query("social_volume_twitter", %{slug: "bitcoin"})

      {:ok, %{sql: sql, args: args}} = Query.get_sql_args(query)

      assert sql =~ ~r/version = \{version:\w+\}/
      assert args["version"] == "1.0"
    end

    test "filters on the requested version" do
      query =
        SqlQuery.last_datetime_computed_at_query(
          "social_volume_twitter",
          %{slug: "bitcoin"},
          version: "2.1"
        )

      {:ok, %{sql: sql, args: args}} = Query.get_sql_args(query)

      assert sql =~ ~r/version = \{version:\w+\}/
      refute sql =~ "version = '1.0'"
      assert args["version"] == "2.1"
    end
  end

  describe "fixed-parameter labelled balance metrics" do
    @from ~U[2026-10-01 00:00:00Z]
    @to ~U[2026-10-10 00:00:00Z]

    defp fixed_parameters(metric) do
      [fixed_parameters: Map.fetch!(Registry.fixed_parameters_map(), metric)]
    end

    defp timeseries_sql_args(metric, selector, filters) do
      SqlQuery.timeseries_data_query(
        metric,
        selector,
        @from,
        @to,
        "1d",
        :last,
        filters,
        fixed_parameters(metric)
      )
      |> Query.get_sql_args()
    end

    test "one label for all assets is derived from the label key" do
      {:ok, %{sql: sql, args: args}} =
        timeseries_sql_args("combined_historical_balance_funds", %{slug: "bitcoin"}, [])

      assert sql =~ "tuple({fixed_label_fqn:String})"
      assert args["fixed_label_fqn"] == "santiment/fund:v1"
      refute sql =~ "labeled_balances_filtered"
    end

    test "one label per asset is derived from the label key and the asset" do
      {:ok, %{sql: sql, args: args}} =
        timeseries_sql_args("historical_balance_whales_usd", %{slug: "ethereum"}, [])

      assert sql =~ "dictGetString('asset_metadata_dict', 'name', asset_id)"
      assert args["fixed_label_key"] == "whale_usd_balance"
    end

    test "a provided label_fqn is used instead of the fixed parameters" do
      {:ok, %{sql: sql, args: args}} =
        timeseries_sql_args(
          "historical_balance_whales_usd",
          %{slug: "ethereum", label_fqn: "santiment/whale_usd_balance(ethereum):v1"},
          label_fqn: "santiment/whale_usd_balance(ethereum):v1"
        )

      refute Map.has_key?(args, "fixed_label_key")
      assert sql =~ "dictGetUInt64('default.labels_by_fqn', 'label_id', tuple({label_fqn_"
    end

    test "owner metrics require a label_fqn" do
      assert_raise Sanbase.Metric.CatchableError, ~r/requires a 'labelFqn'/, fn ->
        timeseries_sql_args("historical_balance_centralized_exchanges", %{slug: "bitcoin"}, [])
      end
    end

    test "the per-slug query applies the fixed parameters" do
      metric = "combined_historical_balance_funds"

      {:ok, %{args: args}} =
        SqlQuery.timeseries_data_per_slug_query(
          metric,
          ["bitcoin", "ethereum"],
          @from,
          @to,
          "1d",
          :last,
          [],
          fixed_parameters(metric)
        )
        |> Query.get_sql_args()

      assert args["fixed_label_fqn"] == "santiment/fund:v1"
    end

    test "the aggregated query applies the fixed parameters" do
      metric = "historical_balance_whales_usd"

      {:ok, %{args: args}} =
        SqlQuery.aggregated_timeseries_data_query(
          metric,
          ["ethereum", "chainlink"],
          @from,
          @to,
          :last,
          [],
          fixed_parameters(metric)
        )
        |> Query.get_sql_args()

      assert args["fixed_label_key"] == "whale_usd_balance"
    end

    test "available label fqns" do
      sql_args = fn metric, slug ->
        fixed = Map.fetch!(Registry.fixed_parameters_map(), metric)

        query =
          if slug,
            do: SqlQuery.available_label_fqns_for_fixed_parameters_query(metric, slug, fixed),
            else: SqlQuery.available_label_fqns_for_fixed_parameters_query(metric, fixed)

        {:ok, result} = Query.get_sql_args(query)
        result
      end

      assert %{args: %{"fqn" => "santiment/centralized_exchange:v1"}} =
               sql_args.("combined_historical_balance_centralized_exchanges", "bitcoin")

      assert %{sql: sql, args: %{"slug" => "ethereum"}} =
               sql_args.("historical_balance_whales_usd", "ethereum")

      assert sql =~ "fqn = concat("

      assert %{sql: sql} = sql_args.("historical_balance_whales_usd", nil)
      assert sql =~ "key = {label_key:String}"

      assert %{sql: sql, args: %{"label_key" => "owner"}} =
               sql_args.("historical_balance_decentralized_exchanges", "ethereum")

      assert sql =~ "labeled_intraday_metrics_v2"

      for metric <- Registry.fixed_labels_parameters_metrics_mapset() do
        refute sql_args.(metric, nil).sql =~ "labeled_balances_filtered"
      end
    end
  end
end
