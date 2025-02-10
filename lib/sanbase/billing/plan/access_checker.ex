defmodule Sanbase.Billing.Plan.AccessChecker do
  @moduledoc """
  """
  alias Sanbase.Billing.Plan.CustomAccessChecker
  alias Sanbase.Billing.Plan.StandardAccessChecker

  @type query_or_argument :: {:metric, String.t()} | {:signal, String.t()} | {:query, Atom.t()}
  @type requested_product :: String.t()
  @type subscription_product :: String.t()
  @type product_code :: String.t()
  @type plan_name :: String.t()

  @doc ~s"""
  Check if a query full access is given only to users with a plan higher than free.

  If a metric is not restricted, then the `from` and `to` parameters do not need to be
  checked and modified. A restriction might be "only the last 2 years of data are available".
  """
  @spec restricted?(query_or_argument) :: boolean()
  def restricted?(query_or_argument) do
    StandardAccessChecker.restricted?(query_or_argument)
  end

  @doc ~s"""
  """
  @spec plan_has_access?(query_or_argument, requested_product, plan_name) :: boolean()
  def plan_has_access?(query_or_argument, requested_product, plan_name) do
    case plan_name do
      "CUSTOM_" <> _ ->
        CustomAccessChecker.plan_has_access?(query_or_argument, requested_product, plan_name)

      _ ->
        StandardAccessChecker.plan_has_access?(query_or_argument, requested_product, plan_name)
    end
  end

  @doc ~s"""
  """
  @spec min_plan(query_or_argument, product_code) :: plan_name
  def min_plan(query_or_argument, product_code) do
    # This `min_plan` does not make sense for Custom Plans as there the
    # plans are not ordered in any way
    StandardAccessChecker.min_plan(product_code, query_or_argument)
  end

  @spec get_available_metrics_for_plan(plan_name, product_code, Atom.t()) :: list(binary())
  def get_available_metrics_for_plan(plan_name, product_code, restriction_type \\ :all)

  def get_available_metrics_for_plan(plan_name, product_code, restriction_type) do
    case plan_name do
      "CUSTOM_" <> _ ->
        CustomAccessChecker.get_available_metrics_for_plan(
          plan_name,
          product_code,
          restriction_type
        )

      _ ->
        StandardAccessChecker.get_available_metrics_for_plan(
          plan_name,
          product_code,
          restriction_type
        )
    end
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
    case plan_name do
      "CUSTOM_" <> _ ->
        CustomAccessChecker.historical_data_in_days(
          query_or_argument,
          requested_product,
          subscription_product,
          plan_name
        )

      _ ->
        StandardAccessChecker.historical_data_in_days(
          query_or_argument,
          requested_product,
          subscription_product,
          plan_name
        )
    end
  end

  @doc """
  If the result from this function is nil, then no restrictions are applied.
  Respectively the `restrictedTo` field has a value of nil as well.
  """
  @spec realtime_data_cut_off_in_days(
          query_or_argument,
          requested_product,
          subscription_product,
          plan_name()
        ) ::
          non_neg_integer() | nil
  def realtime_data_cut_off_in_days(query_or_argument, requested_product, subscription_product, plan_name) do
    case plan_name do
      "CUSTOM_" <> _ ->
        CustomAccessChecker.realtime_data_cut_off_in_days(
          query_or_argument,
          requested_product,
          subscription_product,
          plan_name
        )

      _ ->
        StandardAccessChecker.realtime_data_cut_off_in_days(
          query_or_argument,
          requested_product,
          subscription_product,
          plan_name
        )
    end
  end
end
