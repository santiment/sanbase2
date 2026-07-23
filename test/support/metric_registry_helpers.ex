defmodule Sanbase.MetricRegistryHelpers do
  @moduledoc """
  Test helpers for creating metric registry rows.
  """

  @doc """
  Creates a metric registry row. Accepts a metric name or an attrs map with a
  required `:metric` key; any other attrs override the defaults.
  """
  def create_registry_metric(metric) when is_binary(metric) do
    create_registry_metric(%{metric: metric})
  end

  def create_registry_metric(attrs) when is_map(attrs) do
    defaults = %{
      internal_metric: Map.fetch!(attrs, :metric) <> "_internal",
      human_readable_name: "Human name",
      min_interval: "5m",
      tables: [%{name: "daily_metrics_v2"}],
      default_aggregation: "avg",
      access: "free",
      has_incomplete_data: false,
      data_type: "timeseries"
    }

    {:ok, registry} = Sanbase.Metric.Registry.create(Map.merge(defaults, attrs))
    registry
  end
end
