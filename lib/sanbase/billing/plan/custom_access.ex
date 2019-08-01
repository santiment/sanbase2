defmodule Sanbase.Billing.Plan.CustomAccess do
  @moduledoc ~s"""
  Provide per-query custom access configuration.

  Some queries have custom access logic. For example for MVRV we're showing
  everything except the last 30 days for free users.

  In order to add a new custom metric the description must be added under a new
  `@metric` module attribute. This attribute has the `accumulate: true` option
  so new definitions are added to a list. In the end this module attribute is
  traversed and the result is a map with the metric name as a key and the stats
  as value.

  The following keys must be present:
  - metric name
  - accessible_by_plan - a list of plans that have access to the query. This
    includes partial access, too.
  - plan_full_access - the lowest plan providing full access
  - plan_access - a map where the key is a plan name and the value is a map with
    the `historical_data_in_days` and/or `realtime_data_cut_off_in_days` keys.
    If a plan is missing it means that it has no restrictions. If a field in a plan
    is missing it means that it is not restricted
  """

  import Sanbase.Billing.Plan, only: [sort_plans: 1]
  Module.register_attribute(__MODULE__, :metric, accumulate: true)

  @metric %{
    metric_name: [:mvrv_ratio, :realized_value],
    accessible_by_plan: [:free, :basic, :pro, :premium, :enterprise] |> sort_plans(),
    plan_full_access: :pro,
    plan_access: %{
      free: %{realtime_data_cut_off_in_days: 30, historical_data_in_days: 365},
      basic: %{realtime_data_cut_off_in_days: 14, historical_data_in_days: 2 * 365}
    }
  }

  @metric %{
    metric_name: [:token_age_consumed, :burn_rate],
    accessible_by_plan: [:free, :basic, :pro, :premium, :enterprise] |> sort_plans(),
    plan_full_access: :basic,
    plan_access: %{
      free: %{realtime_data_cut_off_in_days: 30}
    }
  }

  # Raise an error if the accessbile_by_plan are not all sorted.
  # If they are not sorted this can lead to issues such as wrong
  # `lowest_plan_with_access`
  @metric
  |> Enum.each(fn %{accessible_by_plan: plans} = stats ->
    if sort_plans(plans) != plans do
      require Sanbase.Break, as: Break

      Break.break("""
      The order of the plans inside #{inspect(stats.metric_name)} definition is not sorted. This will
      lead to not desired behavior when checking if a plan has access to a query.
      """)
    end
  end)

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
