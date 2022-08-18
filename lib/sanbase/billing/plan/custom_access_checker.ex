defmodule Sanbase.Billing.Plan.CustomAccessChecker do
  @moduledoc """
  """

  alias Sanbase.Billing.Plan.CustomPlan

  @type plan_name :: String.t()
  @type product_code :: String.t()
  @type query_or_argument :: {:metric, String.t()} | {:signal, String.t()} | {:query, atom()}

  def is_restricted?(plan_name, product_code, query_or_argument) do
    # metrics/queries/signals have free/restricted access base
    restricted_access_as_plan = CustomPlan.Access.restricted_access_as_plan(plan_name)

    Sanbase.Billing.Plan.StandardAccessChecker.is_restricted?(
      restricted_access_as_plan,
      product_code,
      query_or_argument
    )
  end

  def plan_has_access?(plan_name, product_code, query_or_argument) do
    CustomPlan.Access.plan_has_access?(plan_name, product_code, query_or_argument)
  end

  def get_available_metrics_for_plan(plan_name, product_code, restriction_type) do
    CustomPlan.Access.get_available_metrics_for_plan(plan_name, product_code, restriction_type)
  end

  def is_historical_data_freely_available?(plan_name, product_code, query_or_argument) do
    restricted_access_as_plan = CustomPlan.Access.restricted_access_as_plan(plan_name)

    Sanbase.Billing.Plan.StandardAccessChecker.is_historical_data_freely_available?(
      restricted_access_as_plan,
      product_code,
      query_or_argument
    )
  end

  def is_realtime_data_freely_available?(plan_name, product_code, query_or_argument) do
    restricted_access_as_plan = CustomPlan.Access.restricted_access_as_plan(plan_name)

    Sanbase.Billing.Plan.StandardAccessChecker.is_realtime_data_freely_available?(
      restricted_access_as_plan,
      product_code,
      query_or_argument
    )
  end

  @doc """
  If the result from this function is nil, then no restrictions are applied.
  Respectively the `restrictedFrom` field has a value of nil as well.
  """
  @spec historical_data_in_days(plan_name, product_code, query_or_argument) ::
          non_neg_integer() | nil
  def historical_data_in_days(plan_name, product_code, query_or_argument) do
    CustomPlan.Access.historical_data_in_days(plan_name, product_code, query_or_argument)
  end

  @doc """
  If the result from this function is nil, then no restrictions are applied.
  Respectively the `restrictedTo` field has a value of nil as well.
  """
  @spec realtime_data_cut_off_in_days(plan_name, product_code, query_or_argument) ::
          non_neg_integer() | nil
  def realtime_data_cut_off_in_days(plan_name, product_code, query_or_argument) do
    CustomPlan.Access.realtime_data_cut_off_in_days(plan_name, product_code, query_or_argument)
  end
end
