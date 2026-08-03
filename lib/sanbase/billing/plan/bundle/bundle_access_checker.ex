defmodule Sanbase.Billing.Plan.BundleAccessChecker do
  @moduledoc ~s"""
  Access checking for bundle plans.

  Mirrors the public surface of `Sanbase.Billing.Plan.CustomAccessChecker` so
  that `Sanbase.Billing.Plan.AccessChecker` can dispatch to either uniformly.

  `plan_has_access?` is implemented. The rest still raise - see
  `Sanbase.Billing.Plan.Bundle` for why, and
  `docs/composable-api-plans-handover.md` task BA for what replaces them.
  """

  alias Sanbase.Billing.Plan.Bundle
  alias Sanbase.Billing.Plan.Bundle.Entitlement

  @type query_or_argument :: {:metric, String.t()} | {:signal, String.t()} | {:query, atom()}

  @doc ~s"""
  Whether a bundle may use this metric, query or signal.

  The product is not consulted. A bundle's entitlement lists exactly what was
  bought, and unlike the standard plans the same answer holds on both products.

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

  def historical_data_in_days(
        _query_or_argument,
        _requested_product,
        _subscription_product,
        plan_name
      ),
      do: Bundle.not_implemented!(:historical_data_in_days, plan_name)

  def realtime_data_cut_off_in_days(
        _query_or_argument,
        _requested_product,
        _subscription_product,
        plan_name
      ),
      do: Bundle.not_implemented!(:realtime_data_cut_off_in_days, plan_name)
end
