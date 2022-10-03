defmodule Sanbase.Billing.Plan.MVRVAccess do
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

  Module.register_attribute(__MODULE__, :metric, accumulate: true)

  # MVRV and RV metrics from the graphql schema and from metrics .json file
  # The other time-bound `mvrv_usd_*` and `realized_value_usd_*` are removed from custom metrics.
  @metric %{
    metric_name: [
      {:query, :mvrv_ratio},
      {:query, :realized_value},
      {:metric, "mvrv_usd"},
      {:metric, "realized_value_usd"}
    ],
    plan_access: %{
      "FREE" => %{realtime_data_cut_off_in_days: 30, historical_data_in_days: 365},
      "BASIC" => %{realtime_data_cut_off_in_days: 14, historical_data_in_days: 2 * 365}
    }
  }

  # Token age consumed metrics from the graphql schema and from metrics .json file
  @metric %{
    metric_name: [{:query, :token_age_consumed}, {:query, :burn_rate}, {:metric, "age_destroyed"}],
    plan_access: %{
      "FREE" => %{realtime_data_cut_off_in_days: 30}
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
