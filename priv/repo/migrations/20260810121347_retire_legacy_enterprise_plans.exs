defmodule Sanbase.Repo.Migrations.RetireLegacyEnterprisePlans do
  use Ecto.Migration

  @moduledoc ~s"""
  Rename `ENTERPRISE_BASIC` (105) and `ENTERPRISE_PLUS` (106) out of the
  `ENTERPRISE` namespace so the new Enterprise tier can own it.

  Those two rows were added in 2022 by
  `20220620132733_add_new_enterprise_api_plans.exs` at $1,500 and $2,500 a month
  and were never wired into anything. No access checker, quota map, complexity
  divider, MCP class or `plan_name/1` clause has ever mentioned them, which means
  they were also broken: `Sanbase.Billing.Plan.plan_name/1` had no clause for
  either name, so a subscriber to one of them would have raised `CaseClauseError`
  on every authenticated request. They were nevertheless returned by
  `product_with_plans/0` and therefore listed on the pricing page and reachable
  through `subscribe(planId: 105)`. On production one subscription has ever
  existed on 105, and it is canceled.

  ## Why rename rather than delete

  `subscriptions` rows reference these plan ids. That one historical subscription
  would either block the delete on the foreign key or lose its plan, and neither
  is worth doing to a billing record. Renaming retires the names while leaving the
  history intact and readable.

  After this, `ENTERPRISE%` is safe to match by prefix. That matters, because the
  sale switch (`Sanbase.Billing.Plan.SaleControls`), the `productsWithPlans`
  exclusion and the legacy-replacement job all match the new offering that way. A
  row still called `ENTERPRISE_BASIC` would have joined the new offering by
  accident: `bundle_plans_active?/0` would have returned true whenever 105 was
  `is_private = false`, permanently disabling the admin off-switch for bundles and
  Institutional as well, and `stale_replaced_subscriptions/0` would have treated an
  `ENTERPRISE_BASIC` holder as a new-offering customer and canceled their other
  SanAPI subscription with proration.

  The rows are also marked private and deprecated. Neither field is what delists
  them, though - `product_with_plans/0` applies `is_deprecated` only to the Business
  names, and `is_private` is enforced nowhere. The `RETIRED_` prefix is what does
  the work: `Plan.product_with_plans/0` excludes it by name and
  `Subscription.ensure_plan_is_for_sale/2` refuses it, so the rows are neither
  listed nor buyable by id. The flags are set for the benefit of anyone reading the
  table directly.

  See task EP of docs/composable-api-plans-handover.md.
  """

  @legacy_plan_ids [105, 106]

  def up do
    execute("""
    UPDATE plans
    SET name = 'RETIRED_' || name, is_private = true, is_deprecated = true
    WHERE id IN (#{Enum.join(@legacy_plan_ids, ", ")})
      AND name LIKE 'ENTERPRISE%'
    """)
  end

  # `regexp_replace` anchored at the start rather than `replace/3`, which is a global
  # substring replace in Postgres and would eat a `RETIRED_` occurring anywhere else
  # in the name. `is_private` is restored too: the rows were public before this ran,
  # which is how they came to be on the pricing page in the first place, so leaving
  # it set would make `down` something other than an inverse of `up`.
  def down do
    execute("""
    UPDATE plans
    SET name = regexp_replace(name, '^RETIRED_', ''),
        is_private = false,
        is_deprecated = false
    WHERE id IN (#{Enum.join(@legacy_plan_ids, ", ")})
      AND name LIKE 'RETIRED_ENTERPRISE%'
    """)
  end
end
