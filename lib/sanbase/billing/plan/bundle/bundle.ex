defmodule Sanbase.Billing.Plan.Bundle do
  @moduledoc ~s"""
  Composable API data packages ("bundles").

  A bundle subscription's entitlement is **not** encoded in its plan name. The
  `plans` row is a marker named `BUNDLE`; the entitlement is decoded from the
  subscription's items. See `docs/composable-api-plans-handover.md` §5.

  ## Current state

  Only the *dispatch* is implemented. `Sanbase.Billing.Plan.type/1` classifies
  `BUNDLE*` names as `:bundle`, and every access and quota function routes that
  case here, where it raises `NotImplementedError`.

  This is deliberate. The alternative - letting bundle plans fall through to the
  standard ladder - would silently grant a paying customer roughly FREE-tier
  access with no error anywhere. A loud, specific failure is the correct
  behavior until the entitlement resolver exists.

  `Sanbase.Billing.PlanTypeDispatchTest` asserts that every one of those sites
  reaches this module, which is what proves no site was missed. That test is the
  checklist for implementing the real path: as each function is implemented, its
  entry moves out of the "not implemented" list.
  """

  @equivalent_standard_plan "PRO"

  @doc ~s"""
  The standard plan a bundle behaves like for everything that is **not** metric,
  query or signal access and **not** the API call quota.

  Those two things come from the entitlement, because they are what the customer
  actually chose. Everything else - how many alerts they can create, how much
  query credit they get, which ClickHouse repo their queries run against, and
  their whole Sanbase experience - has no per-package answer and needs one
  anyway.

  Product's answer (§15 Q5): the same as a SanAPI PRO customer who has no
  Sanbase subscription. Bundles are priced against PRO, so PRO is what they get.

  This mirrors what already happens for `CUSTOM_*` plans, which resolve to their
  `restricted_access_as_plan` for exactly the same reason - see
  `Sanbase.Queries.Authorization.fetch_base_plan_for_custom/1` and
  `SanbaseWeb.Graphql.AuthPlug.effective_plan_name/2`.
  """
  @spec equivalent_standard_plan() :: String.t()
  def equivalent_standard_plan, do: @equivalent_standard_plan

  defmodule NotImplementedError do
    @moduledoc """
    Raised when a bundle plan reaches an access or quota function that has not
    been implemented for bundles yet.
    """
    defexception [:message]
  end

  defmodule MissingEntitlementError do
    @moduledoc """
    Raised when a bundle subscription reaches an access or quota check without a
    stored entitlement.

    This is always a bug: either the subscription was never synced after its
    items changed, or a caller failed to pass the entitlement through. It is
    raised rather than defaulted because the only available default is the
    standard plan ladder, which would silently give a paying customer roughly
    free-tier access.
    """
    defexception [:message]
  end

  @doc ~s"""
  Raise because a bundle subscription arrived without its stored entitlement.

  `site` identifies the function that was reached, so the failure names the
  caller that failed to pass it through rather than surfacing as a
  `FunctionClauseError` further along.

  Distinct from `not_implemented!/2` on purpose: that one means the bundle path
  for a feature does not exist yet, this one means the path exists but its input
  is missing. The two have different fixes, so they are different errors.
  """
  @spec missing_entitlement!(atom()) :: no_return()
  def missing_entitlement!(site) do
    raise MissingEntitlementError,
      message: """
      A bundle subscription reached #{inspect(site)} with no stored entitlement.

      Either the subscription was not re-synced after its items changed, or the
      entitlement was not passed through from the request context. See §5.8 of
      docs/composable-api-plans-handover.md.
      """
  end

  @doc ~s"""
  Raise a descriptive error for an unimplemented bundle code path.

  `site` identifies the function that was reached, so the failure names the
  missing implementation rather than surfacing as a `CaseClauseError` several
  frames away from the cause.
  """
  @spec not_implemented!(atom() | {atom(), term()}, String.t()) :: no_return()
  def not_implemented!(site, plan_name) do
    raise NotImplementedError,
      message: """
      Bundle plans are not implemented yet.

        site: #{inspect(site)}
        plan: #{inspect(plan_name)}

      The plan-type dispatch for bundles is in place, but the entitlement
      resolver that decodes subscription items is not. Implementing it is task
      EN/BA in docs/composable-api-plans-handover.md.
      """
  end
end
