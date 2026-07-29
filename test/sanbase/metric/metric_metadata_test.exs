defmodule Sanbase.MetricMetadataTest do
  use Sanbase.DataCase, async: true

  import Sanbase.Factory, only: [rand_str: 0]

  alias Sanbase.Metric

  test "can fetch metadata for all available metrics" do
    metrics = Metric.available_metrics()
    results = for metric <- metrics, do: Metric.metadata(metric)
    assert Enum.all?(results, &match?({:ok, _}, &1))
  end

  test "cannot fetch metadata for not available metrics" do
    rand_metrics = Enum.map(1..100, fn _ -> rand_str() end)
    rand_metrics = rand_metrics -- Metric.available_metrics()

    results = for metric <- rand_metrics, do: Metric.metadata(metric)

    assert Enum.all?(results, &match?({:error, _}, &1))
  end

  test "metadata properties" do
    metrics = Metric.available_metrics()
    aggregations = Metric.available_aggregations()

    for metric <- metrics do
      {:ok, metadata} = Metric.metadata(metric)
      assert metadata.default_aggregation in aggregations
      assert metadata.min_interval in ["1s", "1m", "5m", "15m", "1h", "6h", "8h", "1d", "7d"]
    end
  end

  test "every metadata map has all the keys described by the behaviour" do
    keys = [
      :metric,
      :internal_metric,
      :min_interval,
      :status,
      :default_aggregation,
      :available_aggregations,
      :available_selectors,
      :required_selectors,
      :data_type,
      :complexity_weight,
      :stabilization_period,
      :has_incomplete_data,
      :is_label_fqn_metric,
      :is_timebound,
      :can_mutate,
      :is_deprecated,
      :hard_deprecate_after,
      :docs
    ]

    for metric <- Metric.available_metrics() do
      {:ok, metadata} = Metric.metadata(metric)
      missing_keys = keys -- Map.keys(metadata)

      assert missing_keys == [],
             "The metadata of #{metric} is missing the keys: #{inspect(missing_keys)}"
    end
  end
end
