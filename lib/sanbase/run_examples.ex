defmodule Sanbase.RunExamples do
  @moduledoc ~s"""
  This module is used in local env to test that the SQL queries are not broken and are
  running. The quereies here **must** make a DB request in order to properly test the SQL.
  Do not run in tests, as if mocked, the purpose of this module would be lost.
  """
  @queries [
    :basic_metric_queries,
    :trending_words,
    :top_holders,
    :asset_prices,
    :price_pair_sql,
    :twitter,
    :github,
    :historical_balance,
    :uniswap,
    :histograms
  ]
  def run do
    original_level = Application.get_env(:logger, :level)

    IO.puts("""
    Start running a set of queries that hit the real databases.
    ==================================================
    """)

    try do
      Logger.configure(level: :warning)

      {t, _result} =
        :timer.tc(fn ->
          Sanbase.Parallel.map(@queries, &measure_run(&1),
            max_concurrency: System.schedulers(),
            ordered: false,
            timeout: 60_000
          )
        end)

      IO.puts("""
      ==================================================
      Finish running the whole set of queries.
      Time spent: #{Float.round(t / 1_000_000, 2)} seconds
      """)
    rescue
      error ->
        IO.puts("Error running the example queries: #{Exception.message(error)}")
    after
      Logger.configure(level: original_level)
    end

    :ok
  end

  defp measure_run(arg) do
    IO.puts("Start running #{arg}")

    {t, _val} = :timer.tc(fn -> do_run(arg) end)

    IO.puts("Finish running #{arg}. Took #{t / 1000}ms")
  end

  # Implement a do_run for each of the values in @queries
  defp do_run(:basic_metric_queries) do
    for metric <- [
          "price_usd",
          "daily_active_addresses",
          "active_addresses_24h",
          "dev_activity",
          "dev_activity_1d",
          "dev_activity_contributors_count"
        ] do
      {:ok, [_ | _]} =
        Sanbase.Metric.timeseries_data(
          metric,
          %{slug: "ethereum"},
          ~U[2023-01-01 00:00:00Z],
          ~U[2023-01-05 00:00:00Z],
          "1d"
        )

      {:ok, _} =
        Sanbase.Metric.aggregated_timeseries_data(
          metric,
          %{slug: "ethereum"},
          Timex.shift(Timex.now(), days: -2),
          Timex.now()
        )

      {:ok, _} = Sanbase.Metric.first_datetime(metric, %{slug: "ethereum"}, [])

      {:ok, _} =
        Sanbase.Metric.last_datetime_computed_at(
          metric,
          %{slug: "ethereum"},
          []
        )

      {:ok, :success}
    end
  end

  defp do_run(:trending_words) do
    {:ok, [_ | _]} =
      Sanbase.SocialData.TrendingWords.get_project_trending_history(
        "bitcoin",
        ~U[2023-01-23 00:00:00Z],
        ~U[2023-01-30 00:00:00Z],
        "1d",
        10
      )

    {:ok, [_ | _]} =
      Sanbase.SocialData.TrendingWords.get_word_trending_history(
        "bitcoin",
        ~U[2023-01-01 00:00:00Z],
        ~U[2023-01-30 00:00:00Z],
        "1d",
        10
      )

    {:ok, %{}} =
      Sanbase.SocialData.TrendingWords.get_trending_words(
        ~U[2023-01-01 00:00:00Z],
        ~U[2023-01-05 00:00:00Z],
        "6h",
        10
      )

    {:ok, :success}
  end

  defp do_run(:top_holders) do
    {:ok, _} =
      Sanbase.Clickhouse.TopHolders.top_holders(
        "ethereum",
        ~U[2023-01-01 00:00:00Z],
        ~U[2023-01-03 00:00:00Z],
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
          ~U[2023-01-01 00:00:00Z],
          ~U[2023-01-03 00:00:00Z],
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
        ~U[2023-01-01 00:00:00Z],
        ~U[2023-01-02 00:00:00Z]
      )

    {:ok, _} =
      Sanbase.Price.aggregated_timeseries_data(
        "ethereum",
        ~U[2023-01-01 00:00:00Z],
        ~U[2023-01-02 00:00:00Z]
      )

    {:ok, _} =
      Sanbase.Price.timeseries_data(
        "ethereum",
        ~U[2023-01-01 00:00:00Z],
        ~U[2023-01-02 00:00:00Z],
        "12h"
      )

    {:ok, _} =
      Sanbase.Price.timeseries_data(
        "ethereum",
        ~U[2023-01-01 00:00:00Z],
        ~U[2023-01-10 00:00:00Z],
        "toStartOfWeek"
      )

    {:ok, _} =
      Sanbase.Price.aggregated_marketcap_and_volume(
        ["bitcoin", "ethereum"],
        ~U[2023-01-01 00:00:00Z],
        ~U[2023-01-02 00:00:00Z]
      )

    {:ok, _} = Sanbase.Price.first_datetime("ethereum")
    {:ok, _} = Sanbase.Price.last_datetime_computed_at("ethereum")

    {:ok, _} = Sanbase.Price.last_record_before("ethereum", ~U[2023-01-01 00:00:00Z])

    {:ok, :success}
  end

  defp do_run(:price_pair_sql) do
    {:ok, _} =
      Sanbase.PricePair.aggregated_timeseries_data(
        ["bitcoin", "ethereum"],
        "USD",
        ~U[2023-01-01 00:00:00Z],
        ~U[2023-01-02 00:00:00Z]
      )

    {:ok, _} =
      Sanbase.PricePair.aggregated_timeseries_data(
        "ethereum",
        "BTC",
        ~U[2023-01-01 00:00:00Z],
        ~U[2023-01-02 00:00:00Z]
      )

    {:ok, _} =
      Sanbase.PricePair.timeseries_data(
        "ethereum",
        "USD",
        ~U[2023-01-01 00:00:00Z],
        ~U[2023-01-02 00:00:00Z],
        "12h"
      )

    {:ok, _} =
      Sanbase.PricePair.timeseries_data(
        "ethereum",
        "USD",
        ~U[2023-01-01 00:00:00Z],
        ~U[2023-01-10 00:00:00Z],
        "toStartOfWeek"
      )

    {:ok, _} = Sanbase.PricePair.first_datetime("ethereum", "USD")
    {:ok, _} = Sanbase.PricePair.last_datetime_computed_at("ethereum", "USDT")

    {:ok, _} =
      Sanbase.PricePair.last_record_before(
        "ethereum",
        "BTC",
        ~U[2023-01-01 00:00:00Z]
      )

    {:ok, :success}
  end

  defp do_run(:twitter) do
    {:ok, _} =
      Sanbase.Twitter.timeseries_data(
        "santimentfeed",
        ~U[2023-01-01 00:00:00Z],
        ~U[2023-01-02 00:00:00Z],
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
        ~U[2023-01-01 00:00:00Z],
        ~U[2023-01-03 00:00:00Z],
        "1d",
        "None",
        nil
      )

    {:ok, [_ | _]} =
      Sanbase.Clickhouse.Github.github_activity(
        ["santiment"],
        ~U[2023-01-01 00:00:00Z],
        ~U[2023-01-03 00:00:00Z],
        "1d",
        "None",
        nil
      )

    {:ok, %{"santiment" => _}} =
      Sanbase.Clickhouse.Github.total_dev_activity(
        ["santiment"],
        ~U[2023-01-01 00:00:00Z],
        ~U[2023-01-03 00:00:00Z]
      )

    {:ok, %{"santiment" => _, "bitcoin" => _}} =
      Sanbase.Clickhouse.Github.total_github_activity(
        ["santiment", "bitcoin"],
        ~U[2023-01-01 00:00:00Z],
        ~U[2023-01-03 00:00:00Z]
      )

    {:ok, [_ | _]} =
      Sanbase.Clickhouse.Github.dev_activity_contributors_count(
        ["santiment"],
        ~U[2023-01-01 00:00:00Z],
        ~U[2023-01-05 00:00:00Z],
        "1d",
        "None",
        nil
      )

    {:ok, :success}
  end

  defp do_run(:historical_balance) do
    {:ok, [_ | _]} =
      Sanbase.Clickhouse.HistoricalBalance.historical_balance(
        %{slug: "ethereum"},
        "0x0000000000000000000000000000000000000000",
        ~U[2023-01-01 00:00:00Z],
        ~U[2023-01-05 00:00:00Z],
        "1d"
      )

    {:ok, [_ | _]} =
      Sanbase.Clickhouse.HistoricalBalance.balance_change(
        %{slug: "ethereum"},
        "0x0000000000000000000000000000000000000000",
        ~U[2023-01-01 00:00:00Z],
        ~U[2023-01-05 00:00:00Z]
      )

    {:ok, [_ | _]} =
      Sanbase.Clickhouse.HistoricalBalance.usd_value_address_change(
        %{
          infrastructure: "ETH",
          address: "0x0000000000000000000000000000000000000000"
        },
        ~U[2023-01-01 00:00:00Z]
      )

    {:ok, [_ | _]} =
      Sanbase.Clickhouse.HistoricalBalance.usd_value_held_by_address(%{
        infrastructure: "ETH",
        address: "0x0000000000000000000000000000000000000000"
      })

    {:ok, [_ | _]} =
      Sanbase.Clickhouse.HistoricalBalance.assets_held_by_address(%{
        infrastructure: "ETH",
        address: "0x0000000000000000000000000000000000000000"
      })
  end

  defp do_run(:uniswap) do
    # These are slow or crash with too much memory used
    # {:ok, %{}} = Sanbase.Clickhouse.Research.Uniswap.who_claimed()
    # {:ok, %{}} = Sanbase.Clickhouse.Research.Uniswap.value_distribution()

    # {:ok, [_ | _]} =
    #   Sanbase.Clickhouse.Uniswap.MetricAdapter.histogram_data(
    #     "uniswap_top_claimers",
    #     %{slug: "uniswap"},
    #     ~U[2023-01-01 00:00:00Z],
    #     ~U[2023-01-05 00:00:00Z],
    #     "1d",
    #     10
    #   )

    {:ok, _} = Sanbase.Price.first_datetime("uniswap")
    {:ok, _} = Sanbase.Price.last_datetime_computed_at("uniswap")
  end

  defp do_run(:histograms) do
  end
end
