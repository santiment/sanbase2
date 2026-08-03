defmodule Sanbase.Billing.Plan.BundleAccessChecker do
  @moduledoc ~s"""
  Access checking for bundle plans.

  Mirrors the public surface of `Sanbase.Billing.Plan.CustomAccessChecker` so
  that `Sanbase.Billing.Plan.AccessChecker` can dispatch to either uniformly.

  `plan_has_access?` and the two data-window functions are implemented.
  `get_available_metrics_for_plan` still raises - see
  `Sanbase.Billing.Plan.Bundle` for why, and
  `docs/composable-api-plans-handover.md` task BA for what replaces it.

  ## Why the products are ignored

  Every function here takes the product arguments its custom-plan counterpart
  takes, and none of them reads them. A bundle's entitlement lists exactly what
  was bought and the same answer holds on both products. The arguments stay in
  the signatures so `AccessChecker` can dispatch to either checker without
  reshaping its calls.
  """

  alias Sanbase.Billing.Plan.Bundle
  alias Sanbase.Billing.Plan.Bundle.Entitlement

  @type query_or_argument :: {:metric, String.t()} | {:signal, String.t()} | {:query, atom()}

  @doc ~s"""
  Whether a bundle may use this metric, query or signal.

  Without an entitlement this cannot be answered at all, so it raises. Passing
  one is the caller's job - see §5.8 of the handover doc for why the plan name
  alone is not enough.
  """
  def plan_has_access?(query_or_argument, product_code, plan_name, entitlement \\ nil)

  def plan_has_access?(
        query_or_argument,
        _product_code,
        _plan_name,
        %Entitlement{} = entitlement
      ),
      do: Bundle.Access.plan_has_access?(query_or_argument, entitlement)

  def plan_has_access?(_query_or_argument, _product_code, _plan_name, nil),
    do: Bundle.missing_entitlement!(:plan_has_access?)

  def get_available_metrics_for_plan(plan_name, _product_code, _restriction_type),
    do: Bundle.not_implemented!(:get_available_metrics_for_plan, plan_name)

  @doc ~s"""
  How many days of history the bundle can read, or `nil` for no limit.

  The requested metric is not consulted either. Standard plans narrow the window
  per metric; a bundle's window is one number for the whole entitlement (§5.7),
  so there is nothing to look up per item.
  """
  def historical_data_in_days(
        query_or_argument,
        requested_product,
        subscription_product,
        plan_name,
        entitlement \\ nil
      )

  def historical_data_in_days(_query_or_argument, _requested, _subscription, _plan_name, nil),
    do: Bundle.missing_entitlement!(:historical_data_in_days)

  def historical_data_in_days(
        _query_or_argument,
        _requested_product,
        _subscription_product,
        _plan_name,
        %Entitlement{} = entitlement
      ),
      do: Bundle.Access.historical_data_in_days(entitlement)

  @doc ~s"""
  How close to now the bundle can read. `0` means realtime.
  """
  def realtime_data_cut_off_in_days(
        query_or_argument,
        requested_product,
        subscription_product,
        plan_name,
        entitlement \\ nil
      )

  def realtime_data_cut_off_in_days(
        _query_or_argument,
        _requested,
        _subscription,
        _plan_name,
        nil
      ),
      do: Bundle.missing_entitlement!(:realtime_data_cut_off_in_days)

  def realtime_data_cut_off_in_days(
        _query_or_argument,
        _requested_product,
        _subscription_product,
        _plan_name,
        %Entitlement{} = entitlement
      ),
      do: Bundle.Access.realtime_data_cut_off_in_days(entitlement)
end
