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
  @sanbase_equivalent_plan "FREE"

  @doc ~s"""
  The standard SanAPI plan a bundle behaves like for everything that is **not**
  metric, query or signal access and **not** the API call quota.

  Those two things come from the entitlement, because they are what the customer
  actually chose. Everything else on the SanAPI side - how much query credit they
  get, which ClickHouse repo their queries run against, how their query complexity
  is divided, how large a monthly response volume they may pull - has no
  per-package answer and needs one anyway. Bundles are priced against PRO, so PRO
  is what they get.

  **Not the Sanbase answer.** That is `sanbase_equivalent_plan/0`, and the two are
  deliberately separate - see its docs for why collapsing them would be a quiet
  downgrade of a paying customer.

  This mirrors what already happens for `CUSTOM_*` plans, which resolve to their
  `restricted_access_as_plan` for exactly the same reason - see
  `Sanbase.Queries.Authorization.fetch_base_plan_for_custom/1` and
  `SanbaseWeb.Graphql.AuthPlug.effective_plan_name/2`.
  """
  @spec equivalent_standard_plan() :: String.t()
  def equivalent_standard_plan, do: @equivalent_standard_plan

  @doc ~s"""
  The Sanbase plan a bundle customer gets when they have no Sanbase subscription
  of their own: **FREE**.

  A bundle is a SanAPI product. The packages say which *metrics* were bought,
  which means nothing for Sanbase - so the question "what does a bundle customer
  see in Sanbase?" has to be answered by a rule rather than by the entitlement,
  and the rule is that they are not paying for Sanbase.

  ## Why this is a separate function from `equivalent_standard_plan/0`

  Because the two answers are genuinely different, and one constant serving both
  would tie them together. Reading this one everywhere would put a paying API
  customer on FREE's query-complexity divider and FREE's monthly response-size
  cap - a 40x cut - with no error anywhere. Reading the other one everywhere is
  what used to happen, and it gave away the full Sanbase PRO experience with it.

  So there are two: this one is read at exactly the two Sanbase-facing sites
  (`SanbaseWeb.Graphql.AuthPlug.effective_plan_name/2` and
  `Sanbase.Billing.Plan.SanbaseAccessChecker`), and `equivalent_standard_plan/0`
  at the SanAPI ones.

  A bundle customer who also buys a Sanbase subscription is unaffected - their own
  subscription is found first and this never comes up.
  """
  @spec sanbase_equivalent_plan() :: String.t()
  def sanbase_equivalent_plan, do: @sanbase_equivalent_plan

  @doc ~s"""
  What a bundle subscription is made of, for showing to its owner.

  Built from local rows only - the items, the catalog prices for the
  subscription's interval, and the entitlement stored on the subscription - so it
  never calls Stripe. This is the read side of the lifecycle mutations: the account
  page needs to list the packages a customer owns, which of them is leaving at the
  next renewal, and what the resulting API allowance is, and none of that is
  recoverable from the `BUNDLE` marker plan.

  Items scheduled for removal are included, because they keep working until
  `remove_at`; `packages` therefore describes the *current* period. When the
  entitlement has not been resolved yet (a subscription written by hand, or a sync
  that failed) the package list falls back to the items and the limits are `nil`,
  rather than the whole field failing.
  """
  @spec subscription_details(Sanbase.Billing.Subscription.t()) :: map()
  def subscription_details(%Sanbase.Billing.Subscription{} = subscription) do
    alias Sanbase.Billing.Plan.Bundle.Entitlement
    alias Sanbase.Billing.Plan.Bundle.Price
    alias Sanbase.Billing.Subscription.Item

    items = Item.by_subscription(subscription.id)
    prices_by_sku = subscription.plan.interval |> Price.active() |> Map.new(&{&1.sku, &1})
    entitlement = subscription.bundle_entitlement

    package_skus = for %Item{type: :package, sku: sku} <- items, do: sku

    addon =
      Enum.find_value(items, fn %Item{type: type, sku: sku} -> type == :api_calls && sku end)

    %{
      packages: (entitlement && entitlement.packages) || package_skus,
      api_calls_addon: addon,
      api_call_limits: entitlement && Entitlement.api_call_limits(entitlement),
      historical_data_in_days: entitlement && entitlement.historical_data_in_days,
      realtime_data_cut_off_in_days: entitlement && entitlement.realtime_data_cut_off_in_days,
      items:
        Enum.map(items, fn %Item{} = item ->
          price = Map.get(prices_by_sku, item.sku)

          %{
            id: item.id,
            sku: item.sku,
            type: item.type,
            quantity: item.quantity,
            amount: price && price.amount,
            currency: price && price.currency,
            remove_at: item.remove_at,
            inserted_at: item.inserted_at
          }
        end)
    }
  end

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
