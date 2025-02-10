defmodule Sanbase.Billing.Plan.CustomAccessChecker do
  @moduledoc """
  """

  alias Sanbase.Billing.Plan.CustomPlan
  alias Sanbase.Billing.Plan.StandardAccessChecker

  @type query_or_argument :: {:metric, String.t()} | {:signal, String.t()} | {:query, Atom.t()}
  @type requested_product :: String.t()
  @type subscription_product :: String.t()
  @type product_code :: String.t()
  @type plan_name :: String.t()

  def restricted?(query_or_argument) do
    StandardAccessChecker.restricted?(query_or_argument)
  end

  def plan_has_access?(query_or_argument, product_code, plan_name) do
    CustomPlan.Access.plan_has_access?(query_or_argument, product_code, plan_name)
  end

  def get_available_metrics_for_plan(plan_name, product_code, restriction_type) do
    CustomPlan.Access.get_available_metrics_for_plan(plan_name, product_code, restriction_type)
  end

  def historical_data_freely_available?(query_or_argument) do
    StandardAccessChecker.historical_data_freely_available?(query_or_argument)
  end

  def realtime_data_freely_available?(query_or_argument) do
    StandardAccessChecker.realtime_data_freely_available?(query_or_argument)
  end

  @doc """
  If the result from this function is nil, then no restrictions are applied.
  Respectively the `restrictedFrom` field has a value of nil as well.
  """
  @spec historical_data_in_days(
          query_or_argument,
          requested_product,
          subscription_product,
          plan_name
        ) ::
          non_neg_integer() | nil
  def historical_data_in_days(query_or_argument, requested_product, subscription_product, plan_name) do
    CustomPlan.Access.historical_data_in_days(
      query_or_argument,
      requested_product,
      subscription_product,
      plan_name
    )
  end

  @doc """
  If the result from this function is nil, then no restrictions are applied.
  Respectively the `restrictedTo` field has a value of nil as well.
  """
  @spec realtime_data_cut_off_in_days(
          query_or_argument,
          requested_product,
          subscription_product,
          plan_name
        ) ::
          non_neg_integer() | nil
  def realtime_data_cut_off_in_days(query_or_argument, requested_product, subscription_product, plan_name) do
    CustomPlan.Access.realtime_data_cut_off_in_days(
      query_or_argument,
      requested_product,
      subscription_product,
      plan_name
    )
  end
end
