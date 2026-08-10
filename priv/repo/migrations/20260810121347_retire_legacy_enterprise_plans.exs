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

  ## What this migration is and is not responsible for

  It makes the `ENTERPRISE` name unambiguous. It is deliberately not what keeps the
  legacy rows out of the new offering, because a migration cannot be a safety
  property: it has a moment before it runs and it has a `down`.

  The two decisions that would have been dangerous to get wrong - putting the
  offering on sale, and canceling a customer's other subscription - match
  `"ENTERPRISE"` exactly rather than by prefix, so neither depends on this having
  run. That matters most for the sale switch. 105 and 106 are `is_private = false`
  on production (`20220620132733` never set the column and the default is `false`),
  so a prefix there would have made `bundle_plans_active?/0` answer true on their
  strength alone - turning the whole offering on, for bundles and Institutional too,
  with the Deactivate button greyed out because the admin panel reads the same
  answer. See `Sanbase.Billing.Plan.SaleControls`.

  What still reads the prefix is `Plan.product_with_plans/0`, and there the legacy
  rows matching is the desired outcome: it delists them, which is the other half of
  retiring them and which happens on deploy rather than on migrate.

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
