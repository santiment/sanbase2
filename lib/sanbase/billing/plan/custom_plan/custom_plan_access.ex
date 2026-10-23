defmodule Sanbase.Billing.Plan.CustomPlan.Access do
  @moduledoc ~s"""
  Implement the restrictions for the API product
  """

  import Sanbase.Billing.Plan.CustomPlan.Loader, only: [get_data: 2]

  alias Sanbase.Billing.Plan.StandardAccessChecker

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
        _query_or_argument,
        requested_product,
        _subscription_product,
        plan_name
      ) do
    get_data(plan_name, requested_product).restrictions.historical_data_in_days
  end

  def realtime_data_cut_off_in_days(
        _query_or_argument,
        requested_product,
        _subscription_product,
        plan_name
      ) do
    get_data(plan_name, requested_product).restrictions.realtime_data_cut_off_in_days
  end

  def plan_has_access?(query_or_argument, product_code, plan_name) do
    data = get_data(plan_name, product_code)

    in_allow_list? =
      case query_or_argument do
        {:metric, metric} -> metric in data.resolved_metrics
        {:signal, signal} -> signal in data.resolved_signals
        {:query, query} -> to_string(query) in data.resolved_queries
      end

    in_allow_list? and min_plan_max_allowed?(query_or_argument, product_code, data.restrictions)
  end

  def get_available_metrics_for_plan(plan_name, product_code, _restriction_type) do
    data = get_data(plan_name, product_code)

    Enum.filter(
      data.resolved_metrics,
      &min_plan_max_allowed?({:metric, &1}, product_code, data.restrictions)
    )
  end

  # Something with min plan "max" also needs a custom plan restricted as
  # BUSINESS_MAX, in addition to being in the plan's allow-list.
  defp min_plan_max_allowed?(query_or_argument, product_code, restrictions) do
    StandardAccessChecker.min_plan(product_code, query_or_argument) != "MAX" or
      restrictions.restricted_access_as_plan == "BUSINESS_MAX"
  end
end
