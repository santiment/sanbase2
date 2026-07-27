defmodule Sanbase.Billing.Plan.BundleAccessChecker do
  @moduledoc ~s"""
  Access checking for bundle plans.

  Mirrors the public surface of `Sanbase.Billing.Plan.CustomAccessChecker` so
  that `Sanbase.Billing.Plan.AccessChecker` can dispatch to either uniformly.

  Every function currently raises - see `Sanbase.Billing.Plan.Bundle` for why,
  and `docs/composable-api-plans-handover.md` task BA for what replaces it.
  """

  alias Sanbase.Billing.Plan.Bundle

  @type query_or_argument :: {:metric, String.t()} | {:signal, String.t()} | {:query, atom()}

  def plan_has_access?(_query_or_argument, _product_code, plan_name),
    do: Bundle.not_implemented!(:plan_has_access?, plan_name)

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
