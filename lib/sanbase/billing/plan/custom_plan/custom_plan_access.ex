defmodule Sanbase.Billing.Plan.CustomPlan.Access do
  @moduledoc ~s"""
  Implement the restrictions for the API product
  """

  import Sanbase.Billing.Plan.CustomPlan.Loader, only: [get_data: 2]

  def api_call_limits(plan_name, product_code) do
    get_data(plan_name, product_code).restrictions.api_call_limits
  end

  def response_size_limits(_plan_name, _product_code) do
    # TODO: Implement in the custom plan table
    # Also, at the moment the response size limits are applied only to free and trial
    # plans, and there should not be trial custom plans
    %{"minute" => 1000, "hour" => 10_000, "month" => 200_000}
  end

  def restricted_access_as_plan(plan_name, product_code) do
    get_data(plan_name, product_code).restrictions.restricted_access_as_plan
  end

  def historical_data_in_days(
        query_or_argument,
        requested_product,
        subscription_product,
        plan_name
      ) do
    get_data(plan_name, subscription_product).restrictions.historical_data_in_days
  end

  def realtime_data_cut_off_in_days(
        query_or_argument,
        requested_product,
        subscription_product,
        plan_name
      ) do
    get_data(plan_name, subscription_product).restrictions.realtime_data_cut_off_in_days
  end

  def plan_has_access?(query_or_argument, product_code, plan_name) do
    case query_or_argument do
      {:metric, metric} -> metric in get_data(plan_name, product_code).resolved_metrics
      {:signal, signal} -> signal in get_data(plan_name, product_code).resolved_signals
      {:query, query} -> to_string(query) in get_data(plan_name, product_code).resolved_queries
    end
  end

  def get_available_metrics_for_plan(plan_name, product_code, _restriction_type) do
    get_data(plan_name, product_code).resolved_metrics
  end
end
