defmodule Sanbase.RunExamples do
  @moduledoc ~s"""
  This module is used in local env to test that the SQL queries are not broken and are
  running. The quereies here **must** make a DB request in order to properly test the SQL.
  Do not run in tests, as if mocked, the purpose of this module would be lost.
  """
  @queries [
    :basic_metric_queries,
    :available_metrics,
    :trending_words,
    :top_holders,
    :asset_prices,
    :price_pair_sql,
    :twitter,
    :github,
    :historical_balance,
    :uniswap,
    :histograms,
    :api_calls_made,
    :sanqueries,
    :transfers,
    :san_burn_credit_transactions,
    :signals,
    :additional_filters
  ]

  @from ~U[2023-01-01 00:00:00Z]
  @closer_to ~U[2023-01-01 08:00:00Z]
  @to ~U[2023-01-03 00:00:00Z]
  @null_address "0x0000000000000000000000000000000000000000"

  def run(queries \\ :all) do
    break_if_production()

    original_level = Application.get_env(:logger, :level)
    max_concurrency = 4
    timeout_minutes = 10

    IO.puts("""
    Start running a set of queries that hit the real databases.
    Running with #{max_concurrency} concurrent workers.
    Timeout: #{timeout_minutes} minutes
    ============================================================
    """)

    try do
      IO.puts("Configure the log level to :warning")
      Logger.configure(level: :warning)

      queries = if queries == :all, do: @queries, else: queries

      {t, _result} =
        :timer.tc(fn ->
          Sanbase.Parallel.map(queries, &measured_run(&1),
            max_concurrency: max_concurrency,
            ordered: false,
            timeout: :timer.minutes(timeout_minutes)
          )
        end)

      IO.puts("""
      ============================================================
      Finish running the whole set of queries.
      Total time spent: #{to_seconds(t)} seconds
      """)
    rescue
      error ->
        IO.puts("Error running the example queries: #{Exception.message(error)}")
    after
      IO.puts("Configure the log level to back to the original :#{original_level}")

      Logger.configure(level: original_level)
    end

    :ok
  end

  defp break_if_production() do
    postgres = System.get_env("DATABASE_URL") || ""
    ch = System.get_env("CLICKHOUSEDATABASE_URL") || ""
    ch_ro = System.get_env("CLICKHOUSE_READONLY_DATABASE_URL") || ""

    if postgres =~ "production",
      do: raise("Do not run the examples against prod postgres!")

    if ch =~ "production",
      do: raise("Do not run the examples against prod postgres!")

    if ch_ro =~ "production",
      do: raise("Do not run the examples against prod readonly CH!")

    :ok
  end

  defp measured_run(arg) do
    IO.puts(IO.ANSI.format([:light_blue, "Start running #{arg}"]))

    {t, _val} = :timer.tc(fn -> do_run(arg) end)

    IO.puts(
      IO.ANSI.format([
        :light_green,
        "Finish running #{arg}. Took #{to_seconds(t)}s"
      ])
    )
  rescue
    e ->
      IO.puts(
        IO.ANSI.format([
          :red,
          """
          Finish running #{arg} with an error: #{Exception.message(e)}
          Stacktrace:
          #{Exception.format_stacktrace(__STACKTRACE__)}
          """
        ])
      )
  end

  defp to_seconds(microseconds) do
    case microseconds / 1_000_000 do
      sec when sec < 1.0 -> Float.round(sec, 4)
      sec -> Float.round(sec, 2)
    end
  end

  # Implement a do_run for each of the values in @queries
  defp do_run(:basic_metric_queries) do
    for metric <- [
          "price_usd",
          "daily_active_addresses",
          "active_addresses_24h",
          "dev_activity_1d"
        ] do
      {:ok, [_ | _]} =
        Sanbase.Metric.timeseries_data(metric, %{slug: "ethereum"}, @from, @to, "1d")

      {:ok, [_ | _]} =
        Sanbase.Metric.timeseries_data_per_slug(
          metric,
          %{slug: ["ethereum", "bitcoin"]},
          @from,
          @to,
          "1d"
        )

      {:ok, _} =
        Sanbase.Metric.aggregated_timeseries_data(
          metric,
          %{slug: "ethereum"},
          @from,
          @to
        )

      {:ok, _} =
        Sanbase.Metric.aggregated_timeseries_data(
          metric,
          %{slug: ["ethereum", "bitcoin"]},
          @from,
          @to
        )

      {:ok, _} = Sanbase.Metric.first_datetime(metric, %{slug: "ethereum"}, [])

      {:ok, _} = Sanbase.Metric.last_datetime_computed_at(metric, %{slug: "ethereum"}, [])

      {:ok, :success}
    end
  end

  defp do_run(:trending_words) do
    {:ok, _} =
      Sanbase.SocialData.TrendingWords.get_project_trending_history(
        "bitcoin",
        ~U[2023-01-23 00:00:00Z],
        ~U[2023-01-30 00:00:00Z],
        "1d",
        10,
        :all
      )

    {:ok, _} =
      Sanbase.SocialData.TrendingWords.get_word_trending_history(
        "bitcoin",
        @from,
        ~U[2023-01-30 00:00:00Z],
        "1d",
        10,
        :all
      )

    {:ok, %{}} = Sanbase.SocialData.TrendingWords.get_trending_words(@from, @to, "6h", 10, :all)

    {:ok, :success}
  end

  defp do_run(:available_metrics) do
    {:ok, [_ | _]} = Sanbase.Metric.available_metrics_for_selector(%{slug: "ethereum"})
  end

  defp do_run(:top_holders) do
    {:ok, _} =
      Sanbase.Clickhouse.TopHolders.top_holders(
        "ethereum",
        @from,
        @to,
        []
      )

    for metric <- [
          "amount_in_top_holders",
          "amount_in_exchange_top_holders",
          "amount_in_non_exchange_top_holders"
        ] do
      {:ok, _} =
        Sanbase.Clickhouse.TopHolders.MetricAdapter.timeseries_data(
          metric,
          %{slug: "ethereum"},
          @from,
          @to,
          "1d",
          []
        )

      {:ok, _} =
        Sanbase.Clickhouse.TopHolders.MetricAdapter.first_datetime(
          metric,
          %{slug: "ethereum"}
        )

      {:ok, _} =
        Sanbase.Clickhouse.TopHolders.MetricAdapter.last_datetime_computed_at(
          metric,
          %{slug: "ethereum"}
        )
    end

    {:ok, :success}
  end

  defp do_run(:asset_prices) do
    {:ok, _} =
      Sanbase.Price.aggregated_timeseries_data(
        ["bitcoin", "ethereum"],
        @from,
        @to
      )

    {:ok, _} =
      Sanbase.Price.aggregated_timeseries_data(
        "ethereum",
        @from,
        @to
      )

    {:ok, _} =
      Sanbase.Price.aggregated_metric_timeseries_data(
        "ethereum",
        "price_usd",
        @from,
        @to
      )

    {:ok, _} =
      Sanbase.Price.timeseries_data(
        "ethereum",
        @from,
        @to,
        "12h"
      )

    {:ok, _} =
      Sanbase.Price.timeseries_metric_data(
        "ethereum",
        "price_usd",
        @from,
        @to,
        "12h"
      )

    {:ok, _} =
      Sanbase.Price.timeseries_data(
        "ethereum",
        @from,
        ~U[2023-01-10 00:00:00Z],
        "toStartOfWeek"
      )

    {:ok, _} =
      Sanbase.Price.timeseries_metric_data_per_slug(
        ["ethereum", "bitcoin"],
        "price_usd",
        @from,
        @to,
        "12h",
        []
      )

    {:ok, _} =
      Sanbase.Price.aggregated_marketcap_and_volume(
        ["bitcoin", "ethereum"],
        @from,
        @to
      )

    {:ok, _} = Sanbase.Price.first_datetime("ethereum")
    {:ok, _} = Sanbase.Price.last_datetime_computed_at("ethereum")

    {:ok, _} = Sanbase.Price.last_record_before("ethereum", @from)

    {:ok, :success}
  end

  defp do_run(:price_pair_sql) do
    {:ok, _} =
      Sanbase.PricePair.aggregated_timeseries_data(
        ["bitcoin", "ethereum"],
        "USD",
        @from,
        @to
      )

    {:ok, _} =
      Sanbase.PricePair.aggregated_timeseries_data(
        "ethereum",
        "BTC",
        @from,
        @to
      )

    {:ok, _} =
      Sanbase.PricePair.timeseries_data(
        "ethereum",
        "USD",
        @from,
        @to,
        "12h"
      )

    {:ok, _} =
      Sanbase.PricePair.timeseries_data(
        "ethereum",
        "USD",
        @from,
        ~U[2023-01-10 00:00:00Z],
        "toStartOfWeek"
      )

    {:ok, _} =
      Sanbase.PricePair.timeseries_data_per_slug(
        ["ethereum", "bitcoin"],
        "USD",
        @from,
        @to,
        "12h",
        []
      )

    {:ok, _} = Sanbase.PricePair.first_datetime("ethereum", "USD")
    {:ok, _} = Sanbase.PricePair.last_datetime_computed_at("ethereum", "USDT")

    {:ok, _} =
      Sanbase.PricePair.last_record_before(
        "ethereum",
        "BTC",
        @from
      )

    {:ok, :success}
  end

  defp do_run(:twitter) do
    {:ok, _} =
      Sanbase.Twitter.timeseries_data(
        "santimentfeed",
        @from,
        @to,
        "12h"
      )

    {:ok, _} = Sanbase.Twitter.first_datetime("santimentfeed")
    {:ok, _} = Sanbase.Twitter.last_datetime("santimentfeed")
    {:ok, _} = Sanbase.Twitter.last_record("santimentfeed")
  end

  defp do_run(:github) do
    {:ok, [_ | _]} =
      Sanbase.Clickhouse.Github.dev_activity(
        ["santiment"],
        @from,
        @to,
        "1d",
        "None",
        nil
      )

    {:ok, [_ | _]} =
      Sanbase.Clickhouse.Github.github_activity(
        ["santiment"],
        @from,
        @to,
        "1d",
        "None",
        nil
      )

    {:ok, %{"santiment" => _}} =
      Sanbase.Clickhouse.Github.total_dev_activity(
        ["santiment"],
        @from,
        @to
      )

    {:ok, %{"santiment" => _, "bitcoin" => _}} =
      Sanbase.Clickhouse.Github.total_github_activity(
        ["santiment", "bitcoin"],
        @from,
        @to
      )

    {:ok, [_ | _]} =
      Sanbase.Clickhouse.Github.dev_activity_contributors_count(
        ["santiment"],
        @from,
        @to,
        "1d",
        "None",
        nil
      )

    {:ok, %{"santiment" => _}} =
      Sanbase.Clickhouse.Github.total_dev_activity_contributors_count(
        ["santiment"],
        @from,
        @to
      )

    {:ok, [_ | _]} =
      Sanbase.Clickhouse.Github.github_activity_contributors_count(
        ["santiment"],
        @from,
        @to,
        "1d",
        "None",
        nil
      )

    {:ok, %{"santiment" => _}} =
      Sanbase.Clickhouse.Github.total_github_activity_contributors_count(
        ["santiment"],
        @from,
        @to
      )

    for metric <- ["dev_activity", "dev_activity_contributors_count"] do
      {:ok, [_ | _]} =
        Sanbase.Metric.timeseries_data(
          metric,
          %{slug: "ethereum"},
          @from,
          @to,
          "1d"
        )

      {:ok, _} =
        Sanbase.Metric.aggregated_timeseries_data(
          metric,
          %{slug: "ethereum"},
          @from,
          @to
        )

      {:ok, _} = Sanbase.Metric.first_datetime(metric, %{slug: "ethereum"}, [])

      {:ok, _} = Sanbase.Metric.last_datetime_computed_at(metric, %{slug: "ethereum"}, [])
    end

    {:ok, :success}
  end

  defp do_run(:historical_balance) do
    for {slug, address} <- [
          {"ethereum", @null_address},
          {"santiment", @null_address},
          {"xrp", "rMQ98K56yXJbDGv49ZSmW51sLn94Xe1mu1"},
          {"bitcoin", "1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa"}
        ] do
      {:ok, [_ | _]} =
        Sanbase.Clickhouse.HistoricalBalance.historical_balance(
          %{slug: slug},
          address,
          @from,
          @closer_to,
          "1d"
        )
    end

    {:ok, [_ | _]} =
      Sanbase.Clickhouse.HistoricalBalance.balance_change(
        %{slug: "ethereum"},
        @null_address,
        @from,
        @closer_to
      )

    {:ok, [_ | _]} =
      Sanbase.Clickhouse.HistoricalBalance.usd_value_address_change(
        %{infrastructure: "ETH", address: @null_address},
        Timex.shift(Timex.now(), days: -3)
      )

    {:ok, [_ | _]} =
      Sanbase.Clickhouse.HistoricalBalance.usd_value_held_by_address(%{
        infrastructure: "ETH",
        address: @null_address
      })

    {:ok, [_ | _]} =
      Sanbase.Clickhouse.HistoricalBalance.assets_held_by_address(%{
        infrastructure: "ETH",
        address: @null_address
      })

    {:ok, :success}
  end

  defp do_run(:uniswap) do
    # These are slow or crash with too much memory used
    # {:ok, %{}} = Sanbase.Clickhouse.Research.Uniswap.who_claimed()
    # {:ok, %{}} = Sanbase.Clickhouse.Research.Uniswap.value_distribution()

    # {:ok, [_ | _]} =
    #   Sanbase.Clickhouse.Uniswap.MetricAdapter.histogram_data(
    #     "uniswap_top_claimers",
    #     %{slug: "uniswap"},
    #     @from,
    #     @to,
    #     "1d",
    #     10
    #   )

    {:ok, _} = Sanbase.Price.first_datetime("uniswap")
    {:ok, _} = Sanbase.Price.last_datetime_computed_at("uniswap")

    {:ok, :success}
  end

  defp do_run(:histograms) do
    for metric <- [
          "age_distribution",
          "spent_coins_cost",
          "eth2_staked_amount_per_label",
          "eth2_unlabeled_staker_inflow_sources",
          "eth2_staking_pools_usd",
          "eth2_staking_pools_validators_count_over_time",
          "eth2_top_stakers"
        ] do
      {:ok, _} =
        Sanbase.Clickhouse.MetricAdapter.HistogramMetric.histogram_data(
          metric,
          %{slug: "ethereum"},
          ~U[2023-01-01 00:00:00Z],
          ~U[2023-01-01 03:00:00Z],
          "3h",
          1
        )
    end

    {:ok, :success}
  end

  defp do_run(:api_calls_made) do
    {:ok, _} = Sanbase.Clickhouse.ApiCallData.active_users_count(@from, @to)

    {:ok, _} = Sanbase.Clickhouse.ApiCallData.api_call_count(22, @from, @to)

    {:ok, _} = Sanbase.Clickhouse.ApiCallData.api_call_history(22, @from, @to, "1d")

    {:ok, :success}
  end

  defp do_run(:sanqueries) do
    {:ok, _} =
      Sanbase.Dashboard.Query.run(
        """
        SELECT dt, value
        FROM intraday_metrics
        WHERE
          asset_id = (SELECT asset_id FROM asset_metadata WHERE name == {{slug}} LIMIT 1) AND
          metric_id = (SELECT metric_id FROM metric_metadata WHERE name == {{metric}} LIMIT 1)
        LIMIT 2
        """,
        %{slug: "bitcoin", metric: "active_addresses_24h"},
        %{sanbase_user_id: 22}
      )

    {:ok, :success}
  end

  defp do_run(:transfers) do
    {:ok, _} =
      Sanbase.Transfers.top_wallet_transfers(
        "ethereum",
        @null_address,
        @from,
        @to,
        1,
        10,
        :in
      )

    {:ok, _} =
      Sanbase.Transfers.incoming_transfers_summary("ethereum", @null_address, @from, @to, [])

    {:ok, _} =
      Sanbase.Transfers.outgoing_transfers_summary("ethereum", @null_address, @from, @to, [])

    {:ok, _} =
      Sanbase.Transfers.incoming_transfers_summary("santiment", @null_address, @from, @to, [])

    {:ok, _} =
      Sanbase.Transfers.outgoing_transfers_summary("santiment", @null_address, @from, @to, [])

    {:ok, _} = Sanbase.Transfers.top_transfers("santiment", @from, @to, 1, 10)

    {:ok, _} = Sanbase.Transfers.top_transfers("bitcoin", @from, @to, 1, 10)

    {:ok, :success}
  end

  defp do_run(:san_burn_credit_transactions) do
    {:ok, _} = Sanbase.Billing.Subscription.SanBurnCreditTransaction.fetch_burn_trxs()

    {:ok, :success}
  end

  defp do_run(:signals) do
    [_ | _] = Sanbase.Signal.available_signals()

    {:ok, _} =
      Sanbase.Signal.timeseries_data(
        "anomaly_daily_active_addresses",
        %{slug: "ethereum"},
        @from,
        @to,
        "1d",
        []
      )

    {:ok, _} =
      Sanbase.Signal.aggregated_timeseries_data(
        "anomaly_daily_active_addresses",
        %{slug: "ethereum"},
        @from,
        @to,
        []
      )

    {:ok, _} = Sanbase.Signal.available_signals(%{slug: "ethereum"})
    {:ok, _} = Sanbase.Signal.available_slugs("anomaly_daily_active_addresses")

    {:ok, :success}
  end

  defp do_run(:additional_filters) do
    {:ok, _} =
      Sanbase.Metric.aggregated_timeseries_data(
        "labelled_historical_balance",
        %{slug: "ethereum"},
        @from,
        @to,
        additional_filters: [
          label_fqn: ["santiment/owner->Coinbase:v1"]
        ]
      )

    {:ok, _} =
      Sanbase.Clickhouse.Exchanges.top_exchanges_by_balance(
        %{slug: "ethereum"},
        1,
        additional_filters: [
          owner: ["binance"],
          label: ["centralized_exchange"]
        ]
      )
  end
end
