defmodule SanbaseWeb.Graphql.TechIndicatorsTypes do
  use Absinthe.Schema.Notation

  object :price_volume_diff do
    field(:datetime, non_null(:datetime))
    field(:price_volume_diff, :float)
    field(:price_change, :float)
    field(:volume_change, :float)
  end

  enum :anomalies_metrics_enum do
    value(:daily_active_addresses)
    value(:dev_activity)
  end

  @desc ~s"""
  Field `metricValue` is the value from original metric that is considered abnormal.
  """
  object :anomaly_value do
    field(:metric_value, :float)
    field(:datetime, non_null(:datetime))
  end
end
