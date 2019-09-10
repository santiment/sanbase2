defmodule Sanbase.Billing.Plan.CustomAccess do
  @moduledoc ~s"""
  Provide per-query custom access configuration.

  Some queries have custom access logic. For example for Token Age Consumed
  we're showing everything except the last 30 days for free users.

  In order to add a new custom metric the description must be added under a new
  `@metric` module attribute. This attribute has the `accumulate: true` option
  so new definitions are added to a list. In the end this module attribute is
  traversed and the result is a map with the metric name as a key and the stats
  as value.

  The following keys must be present:
  - metric name
  - plan_access - a map where the key is a plan name and the value is a map with
    the `historical_data_in_days` and/or `realtime_data_cut_off_in_days` keys.
    If a plan is missing it means that it has no restrictions. If a field in a plan
    is missing it means that it is not restricted
  """

  @doc documentation_ref: "# DOCS access-plans/index.md"

  import Sanbase.Clickhouse.Metric.Helper,
    only: [mvrv_metrics: 0, realized_value_metrics: 0, token_age_consumed_metrics: 0]

  Module.register_attribute(__MODULE__, :metric, accumulate: true)

  # MVRV and RV metrics from the schema and from Clickhouse
  @metric %{
    metric_name: [:mvrv_ratio, :realized_value] ++ mvrv_metrics() ++ realized_value_metrics(),
    plan_access: %{
      free: %{realtime_data_cut_off_in_days: 30, historical_data_in_days: 365},
      basic: %{realtime_data_cut_off_in_days: 14, historical_data_in_days: 2 * 365}
    }
  }

  # Token age consumed metrics from the shcme and from Clickhouse
  @metric %{
    metric_name: [:token_age_consumed, :burn_rate] ++ token_age_consumed_metrics(),
    plan_access: %{
      free: %{realtime_data_cut_off_in_days: 30}
    }
  }

  @doc ~s"""
  Returns a map where the keys are the atom metric names and values are the
  custom access stats
  """
  @spec get() :: map()
  def get() do
    @metric
    |> Enum.flat_map(fn
      %{metric_name: [_ | _] = names} = stats ->
        Enum.map(names, fn name -> {name, stats |> Map.delete(:metric_name)} end)

      %{metric_name: name} = stats ->
        [{name, stats |> Map.delete(:metric_name)}]
    end)
    |> Map.new()
  end
end
