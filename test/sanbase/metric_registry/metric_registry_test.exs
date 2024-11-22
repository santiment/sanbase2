defmodule Sanbase.MetricRegistyTest do
  use Sanbase.DataCase
  import ExUnit.CaptureLog

  test "creating a new metric" do
    log =
      capture_log(fn ->
        assert {:ok, result} =
                 Sanbase.Metric.Registry.create(%{
                   metric: "my_metric",
                   internal_metric: "my_metric_5m",
                   human_readable_name: "My Metric",
                   min_interval: "5m",
                   tables: [%{name: "daily_metrics_v2"}],
                   default_aggregation: "avg",
                   access: "free",
                   data_type: "timeseries"
                 })

        assert %Sanbase.Metric.Registry{} = result

        assert result.metric == "my_metric"
        assert result.internal_metric == "my_metric_5m"
        assert result.human_readable_name == "My Metric"
        assert result.min_interval == "5m"
        assert result.tables |> hd() |> Map.get(:name) == "daily_metrics_v2"

        # Give it some time so the EventBus subscriber can process the event and produce the logs
        Process.sleep(50)
      end)

    assert log =~ "Metric Registry Change - Event Type: create_metric_registry, Metric: my_metric"
  end

  test "updating a metric" do
    assert {:ok, metric} = Sanbase.Metric.Registry.by_name("price_usd_5m", "timeseries")

    log =
      capture_log(fn ->
        assert {:ok, updated} =
                 Sanbase.Metric.Registry.update(metric, %{
                   min_interval: "11d",
                   tables: [%{name: "new_intraday_metrics"}]
                 })

        assert updated.metric == "price_usd_5m"
        assert updated.min_interval == "11d"

        assert updated.tables |> hd() |> Map.get(:name) == "new_intraday_metrics"

        # Give it some time so the EventBus subscriber can process the event and produce the logs
        Process.sleep(50)
      end)

    assert log =~
             "Metric Registry Change - Event Type: update_metric_registry, Metric: price_usd_5m"
  end
end
