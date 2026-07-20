defmodule Sanbase.MetricTest do
  use Sanbase.DataCase

  import Sanbase.Factory
  import Sanbase.TestHelpers
  import SanbaseWeb.Graphql.TestHelpers

  alias Sanbase.Metric

  @from ~U[2019-01-01 00:00:00Z]
  @to ~U[2019-01-02 00:00:00Z]

  @resp [
    %{datetime: @from, value: 10},
    %{datetime: @to, value: 20}
  ]

  setup_all_with_mocks([
    {Sanbase.Clickhouse.MetricAdapter, [:passthrough],
     timeseries_data: fn _, _, _, _, _, _ -> {:ok, @resp} end},
    {Sanbase.Clickhouse.Github.MetricAdapter, [:passthrough],
     timeseries_data: fn _, _, _, _, _, _ -> {:ok, @resp} end},
    {Sanbase.Twitter.MetricAdapter, [:passthrough],
     timeseries_data: fn _, _, _, _, _, _ -> {:ok, @resp} end},
    {Sanbase.SocialData.MetricAdapter, [:passthrough],
     timeseries_data: fn _, _, _, _, _, _ -> {:ok, @resp} end},
    {Sanbase.Price.MetricAdapter, [:passthrough],
     timeseries_data: fn _, _, _, _, _, _ -> {:ok, @resp} end},
    {Sanbase.PricePair.MetricAdapter, [:passthrough],
     timeseries_data: fn _, _, _, _, _, _ -> {:ok, @resp} end},
    {Sanbase.Clickhouse.TopHolders.MetricAdapter, [:passthrough],
     timeseries_data: fn _, _, _, _, _, _ -> {:ok, @resp} end},
    {Sanbase.BlockchainAddress.MetricAdapter, [:passthrough],
     timeseries_data: fn _, _, _, _, _, _ -> {:ok, @resp} end},
    {Sanbase.Contract.MetricAdapter, [:passthrough],
     timeseries_data: fn _, _, _, _, _, _ -> {:ok, @resp} end}
  ]) do
    []
  end

  setup do
    [project: insert(:random_erc20_project, slug: "santiment")]
  end

  describe "timeseries data" do
    test "can fetch all available metrics with default aggregation", %{project: project} do
      metrics = Metric.available_timeseries_metrics()

      results =
        for metric <- metrics do
          selector = extend_selector_with_required_fields(metric, %{slug: project.slug})
          Metric.timeseries_data(metric, selector, @from, @to, "1d")
        end

      assert Enum.all?(results, &match?({:ok, _}, &1))
    end

    test "cannot fetch available metrics that are not in the available list", _context do
      metrics = Metric.available_timeseries_metrics()
      rand_metrics = Enum.map(1..100, fn _ -> rand_str() end)
      rand_metrics = rand_metrics -- metrics

      results =
        for metric <- rand_metrics do
          Metric.timeseries_data(metric, "santiment", @from, @to, "1d", aggregation: :avg)
        end

      assert Enum.all?(results, &match?({:error, _}, &1))
    end

    test "can use all available aggregations", %{project: project} do
      metrics = Metric.available_timeseries_metrics()

      for _ <- 1..10 do
        metric = metrics |> Enum.random()
        selector = extend_selector_with_required_fields(metric, %{slug: project.slug})
        {:ok, %{available_aggregations: aggregations}} = Metric.metadata(metric)

        results =
          for aggregation <- aggregations do
            Metric.timeseries_data(metric, selector, @from, @to, "1d", aggregation: aggregation)
          end

        assert Enum.all?(results, &match?({:ok, _}, &1))
      end
    end

    test "cannot use aggregation that is not available", %{project: project} do
      # Fetch some available metric
      metric = Metric.available_timeseries_metrics() |> Enum.random()
      selector = extend_selector_with_required_fields(metric, %{slug: project.slug})

      aggregations = Metric.available_aggregations()
      rand_aggregations = Enum.map(1..10, fn _ -> rand_str() |> String.to_atom() end)
      rand_aggregations = rand_aggregations -- aggregations

      results =
        for aggregation <- rand_aggregations do
          Metric.timeseries_data(metric, selector, @from, @to, "1d", aggregation: aggregation)
        end

      assert Enum.all?(results, &match?({:error, _}, &1))
    end

    test "fetch a single metric", %{project: project} do
      metric = Metric.available_timeseries_metrics() |> Enum.random()
      selector = extend_selector_with_required_fields(metric, %{slug: project.slug})
      result = Metric.timeseries_data(metric, selector, @from, @to, "1d")

      assert result == {:ok, @resp}
    end
  end

  describe "data type mismatch" do
    test "cannot fetch a histogram metric as timeseries", %{project: project} do
      assert {:error, error} =
               Metric.timeseries_data("age_distribution", %{slug: project.slug}, @from, @to, "1d")

      assert error =~
               "The metric 'age_distribution' is a histogram metric, not a timeseries metric. " <>
                 "Use the histogramData field to fetch it."
    end

    test "cannot fetch a histogram metric as timeseries per slug", %{project: project} do
      assert {:error, error} =
               Metric.timeseries_data_per_slug(
                 "price_histogram",
                 %{slug: project.slug},
                 @from,
                 @to,
                 "1d"
               )

      assert error =~
               "The metric 'price_histogram' is a histogram metric, not a timeseries metric."
    end

    test "cannot fetch a histogram metric as aggregated timeseries", %{project: project} do
      assert {:error, error} =
               Metric.aggregated_timeseries_data(
                 "spent_coins_cost",
                 %{slug: project.slug},
                 @from,
                 @to
               )

      assert error =~
               "The metric 'spent_coins_cost' is a histogram metric, not a timeseries metric."
    end

    test "cannot fetch a timeseries metric as histogram", %{project: project} do
      assert {:error, error} =
               Metric.histogram_data(
                 "daily_active_addresses",
                 %{slug: project.slug},
                 @from,
                 @to,
                 "1d"
               )

      assert error =~
               "The metric 'daily_active_addresses' is a timeseries metric, not a histogram metric. " <>
                 "Use the timeseriesData field to fetch it."
    end
  end

  describe "available_non_crypto_asset_slugs/2" do
    test "unknown metric returns an error even when no non-crypto assets exist" do
      assert {:error, error} = Metric.available_non_crypto_asset_slugs("unknown_metric_xyz")
      assert error =~ "The metric 'unknown_metric_xyz' is not supported"
    end
  end
end
