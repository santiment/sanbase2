defmodule Sanbase.Billing.Plan.SanbaseAccessChecker do
  @moduledoc ~s"""
  Implement the restrictions for the Sanbase product
  """

  @doc documentation_ref: "# DOCS access-plans/index.md"

  alias Sanbase.Billing.Plan
  alias Sanbase.Alert.UserTrigger

  @free_plan_stats %{
    historical_data_in_days: 2 * 365,
    realtime_data_cut_off_in_days: 30,
    alerts: %{
      limit: 10
    },
    sangraphs_access: false
  }

  @pro_plan_stats %{
    realtime_data_cut_off_in_days: 0,
    alerts: %{
      limit: :no_limit
    },
    access_paywalled_insights: true,
    sangraphs_access: true
  }

  @basic_plan_stats Map.merge(@free_plan_stats, %{access_paywalled_insights: true})

  @custom_plan_stats @pro_plan_stats

  def historical_data_in_days(plan, _query \\ nil) do
    plan_stats(plan)
    |> Map.get(:historical_data_in_days)
  end

  def realtime_data_cut_off_in_days(plan, _query \\ nil) do
    plan_stats(plan)
    |> Map.get(:realtime_data_cut_off_in_days)
  end

  def alerts_limit(plan) do
    plan_stats(plan)
    |> get_in([:alerts, :limit])
  end

  def alerts_limits_not_reached?(user, subscription) do
    created_alerts_count = UserTrigger.triggers_count_for(user)

    subscription.plan
    |> Plan.plan_atom_name()
    |> alerts_limit()
    |> case do
      :no_limit -> true
      limit when is_integer(limit) and created_alerts_count >= limit -> false
      _ -> true
    end
  end

  def can_access_paywalled_insights?(nil), do: false

  def can_access_paywalled_insights?(subscription) do
    subscription.plan
    |> Plan.plan_atom_name()
    |> plan_stats()
    |> Map.get(:access_paywalled_insights, false)
  end

  defp plan_stats(plan) do
    case plan do
      :free -> @free_plan_stats
      :basic -> @basic_plan_stats
      :pro -> @pro_plan_stats
      :pro_plus -> @pro_plan_stats
      :premium -> @custom_plan_stats
      :custom -> @custom_plan_stats
    end
  end
end
