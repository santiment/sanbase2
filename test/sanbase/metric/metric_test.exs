defmodule Sanbase.MetricTest do
  use Sanbase.DataCase

  import Mock
  import Sanbase.Factory

  alias Sanbase.Metric

  @from ~U[2019-01-01 00:00:00Z]
  @to ~U[2019-01-02 00:00:00Z]

  @resp [
    %{datetime: @from, value: 10},
    %{datetime: @to, value: 20}
  ]

  setup_with_mocks([
    {Sanbase.SocialData.SocialVolume, [:passthrough],
     social_volume_projects: fn -> {:ok, ["bitcoin", "santiment"]} end},
    {Sanbase.Clickhouse.Metric, [:passthrough],
     timeseries_data: fn _, _, _, _, _, _ -> {:ok, @resp} end},
    {Sanbase.Clickhouse.Github.MetricAdapter, [:passthrough],
     timeseries_data: fn _, _, _, _, _, _ -> {:ok, @resp} end},
    {Sanbase.Twitter.MetricAdapter, [:passthrough],
     timeseries_data: fn _, _, _, _, _, _ -> {:ok, @resp} end},
    {Sanbase.SocialData.MetricAdapter, [:passthrough],
     timeseries_data: fn _, _, _, _, _, _ -> {:ok, @resp} end},
    {Sanbase.Price.MetricAdapter, [:passthrough],
     timeseries_data: fn _, _, _, _, _, _ -> {:ok, @resp} end},
    {Sanbase.Clickhouse.TopHolders.MetricAdapter, [:passthrough],
     timeseries_data: fn _, _, _, _, _, _ -> {:ok, @resp} end}
  ]) do
    [project: insert(:random_erc20_project, slug: "santiment")]
  end

  describe "timeseries data" do
    test "can fetch all available metrics with default aggregation", %{project: project} do
      metrics = Metric.available_timeseries_metrics()

      results =
        for metric <- metrics do
          Metric.timeseries_data(metric, %{slug: project.slug}, @from, @to, "1d")
        end

      assert Enum.all?(results, &match?({:ok, _}, &1))
    end

    test "cannot fetch available metrics that are not in the available list", _context do
      metrics = Metric.available_timeseries_metrics()
      rand_metrics = Enum.map(1..100, fn _ -> rand_str() end)
      rand_metrics = rand_metrics -- metrics

      results =
        for metric <- rand_metrics do
          Metric.timeseries_data(metric, "santiment", @from, @to, "1d", :avg)
        end

      assert Enum.all?(results, &match?({:error, _}, &1))
    end

    test "can use all available aggregations", %{project: project} do
      metrics = Metric.available_timeseries_metrics()

      for _ <- 1..10 do
        metric = metrics |> Enum.random()
        {:ok, %{available_aggregations: aggregations}} = Metric.metadata(metric)

        results =
          for aggregation <- aggregations do
            Metric.timeseries_data(metric, %{slug: project.slug}, @from, @to, "1d", aggregation)
          end

        assert Enum.all?(results, &match?({:ok, _}, &1))
      end
    end

    test "cannot use aggregation that is not available", %{project: project} do
      # Fetch some available metric
      [metric | _] = Metric.available_timeseries_metrics()
      aggregations = Metric.available_aggregations()
      rand_aggregations = Enum.map(1..10, fn _ -> rand_str() |> String.to_atom() end)
      rand_aggregations = rand_aggregations -- aggregations

      results =
        for aggregation <- rand_aggregations do
          Metric.timeseries_data(metric, %{slug: project.slug}, @from, @to, "1d", aggregation)
        end

      assert Enum.all?(results, &match?({:error, _}, &1))
    end

    test "fetch a single metric", %{project: project} do
      [metric | _] = Metric.available_timeseries_metrics()

      result = Metric.timeseries_data(metric, %{slug: project.slug}, @from, @to, "1d", :avg)

      assert result == {:ok, @resp}
    end
  end
end
