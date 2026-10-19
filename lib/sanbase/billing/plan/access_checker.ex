defmodule Sanbase.Billing.Plan.AccessChecker do
  @moduledoc """
  """
  @type query_or_argument :: {:metric, String.t()} | {:signal, String.t()} | {:query, Atom.t()}
  @type requested_product :: String.t()
  @type subscription_product :: String.t()
  @type product_code :: String.t()
  @type plan_name :: String.t()
  @type entitlement :: Sanbase.Billing.Plan.Bundle.Entitlement.t() | nil
  @type grant :: Sanbase.Billing.Subscription.Grant.t() | nil

  alias Sanbase.Billing.Plan
  alias Sanbase.Billing.Plan.{BundleAccessChecker, CustomAccessChecker, StandardAccessChecker}

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
  Whether the given plan may use this metric, query or signal.

  The last argument is only read by bundle plans, which cannot be identified by
  name - every bundle is named `BUNDLE`, so the entitlement has to be handed in.
  Standard and custom plans ignore it, which is why existing callers can keep
  using the three-argument form unchanged. See §5.8 of
  docs/composable-api-plans-handover.md.
  """
  @spec plan_has_access?(query_or_argument, requested_product, plan_name, entitlement) ::
          boolean()
  def plan_has_access?(query_or_argument, requested_product, plan_name, entitlement \\ nil) do
    case Plan.type(plan_name) do
      :bundle ->
        BundleAccessChecker.plan_has_access?(
          query_or_argument,
          requested_product,
          plan_name,
          entitlement
        )

      :custom ->
        CustomAccessChecker.plan_has_access?(query_or_argument, requested_product, plan_name)

      :standard ->
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

  @doc ~s"""
  Metrics available under this plan.

  The last argument is only read by bundle plans - every bundle is named
  `BUNDLE`, so the entitlement has to be handed in. Standard and custom plans
  ignore it.
  """
  @spec get_available_metrics_for_plan(plan_name, product_code, Atom.t(), entitlement) ::
          list(binary())
  def get_available_metrics_for_plan(
        plan_name,
        product_code,
        restriction_type \\ :all,
        entitlement \\ nil
      )

  def get_available_metrics_for_plan(plan_name, product_code, restriction_type, entitlement) do
    case Plan.type(plan_name) do
      :bundle ->
        BundleAccessChecker.get_available_metrics_for_plan(
          plan_name,
          product_code,
          restriction_type,
          entitlement
        )

      :custom ->
        CustomAccessChecker.get_available_metrics_for_plan(
          plan_name,
          product_code,
          restriction_type
        )

      :standard ->
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

  The last argument is a sales-applied grant (§8 task GR). It is applied *after*
  the plan has answered and can only widen the window - a metric the customer
  bought full history for returns `nil`, which is what "no limit" already means
  everywhere else here. Every other metric keeps the plan's answer, so a caller
  with no grant sees exactly what it saw before.

  This is the one function that needs the grant, because it is the only place a
  history window is decided. `realtime_data_cut_off_in_days/5` needs nothing:
  Institutional is already realtime.
  """
  @spec historical_data_in_days(
          query_or_argument,
          requested_product,
          subscription_product,
          plan_name,
          entitlement,
          grant
        ) ::
          non_neg_integer() | nil
  def historical_data_in_days(
        query_or_argument,
        requested_product,
        subscription_product,
        plan_name,
        entitlement \\ nil,
        grant \\ nil
      ) do
    query_or_argument
    |> plan_historical_data_in_days(
      requested_product,
      subscription_product,
      plan_name,
      entitlement
    )
    |> apply_history_grant(grant, query_or_argument)
  end

  # A grant names metrics, so only a metric can be upgraded by one. Queries and signals
  # carry no history window of their own that a package could have bought.
  defp apply_history_grant(days, nil, _query_or_argument), do: days

  defp apply_history_grant(days, grant, {:metric, metric}) do
    if Sanbase.Billing.Subscription.Grant.full_history?(grant, metric), do: nil, else: days
  end

  defp apply_history_grant(days, _grant, _query_or_argument), do: days

  defp plan_historical_data_in_days(
         query_or_argument,
         requested_product,
         subscription_product,
         plan_name,
         entitlement
       ) do
    case Plan.type(plan_name) do
      :bundle ->
        BundleAccessChecker.historical_data_in_days(
          query_or_argument,
          requested_product,
          subscription_product,
          plan_name,
          entitlement
        )

      :custom ->
        CustomAccessChecker.historical_data_in_days(
          query_or_argument,
          requested_product,
          subscription_product,
          plan_name
        )

      :standard ->
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
          plan_name(),
          entitlement
        ) ::
          non_neg_integer() | nil
  def realtime_data_cut_off_in_days(
        query_or_argument,
        requested_product,
        subscription_product,
        plan_name,
        entitlement \\ nil
      ) do
    case Plan.type(plan_name) do
      :bundle ->
        BundleAccessChecker.realtime_data_cut_off_in_days(
          query_or_argument,
          requested_product,
          subscription_product,
          plan_name,
          entitlement
        )

      :custom ->
        CustomAccessChecker.realtime_data_cut_off_in_days(
          query_or_argument,
          requested_product,
          subscription_product,
          plan_name
        )

      :standard ->
        StandardAccessChecker.realtime_data_cut_off_in_days(
          query_or_argument,
          requested_product,
          subscription_product,
          plan_name
        )
    end
  end
end
