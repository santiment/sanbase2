defmodule Sanbase.Billing.Plan.Bundle do
  @moduledoc ~s"""
  Composable API data packages ("bundles").

  A bundle subscription's entitlement is **not** encoded in its plan name. The
  `plans` row is a marker (`BUNDLE_API`); the entitlement is decoded from the
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

  defmodule NotImplementedError do
    @moduledoc """
    Raised when a bundle plan reaches an access or quota function that has not
    been implemented for bundles yet.
    """
    defexception [:message]
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
