defmodule Sanbase.Clickhouse.Metric.Helper do
  @moduledoc ~s"""
  Provides some helper functions for filtering the clickhouse v2 metrics
  """
  alias Sanbase.Clickhouse.Metric

  def metric_with_name_containing(str) do
    Metric.available_metrics()
    |> Enum.filter(fn metric -> String.contains?(metric, str) end)
  end

  def mvrv_metrics(), do: wrap(["mvrv_usd"])
  def realized_value_metrics(), do: wrap(["realized_value_usd"])
  def token_age_consumed_metrics(), do: wrap(["age_destroyed"])

  defp wrap(list) do
    list
    |> Enum.map(fn name -> {:metric, name} end)
  end
end
