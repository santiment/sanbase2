defmodule Sanbase.Billing.Plan.CustomPlan.Access do
  @moduledoc ~s"""
  Implement the restrictions for the API product
  """

  import Sanbase.Billing.Plan.CustomPlan.Loader, only: [get_data: 1]

  def api_call_limits(plan_name) do
    get_data(plan_name).restrictions.api_call_limits
  end

  def restricted_access_as_plan(plan_name) do
    get_data(plan_name).restrictions.restricted_access_as_plan
  end

  def historical_data_in_days(plan_name, _product_code, _query) do
    get_data(plan_name).restrictions.historical_data_in_days
  end

  def realtime_data_cut_off_in_days(plan_name, _product_code, _query) do
    get_data(plan_name).restrictions.historical_data_in_days
  end

  def plan_has_access?(plan_name, _product_code, query_or_argument) do
    case query_or_argument do
      {:metric, metric} -> metric in get_data(plan_name).resolved_metrics
      {:signal, signal} -> signal in get_data(plan_name).resolved_signals
      {:query, query} -> to_string(query) in get_data(plan_name).resolved_queries
    end
  end

  def get_available_metrics_for_plan(plan_name, _product_code, _restriction_type) do
    get_data(plan_name).resolved_metrics
  end
end
