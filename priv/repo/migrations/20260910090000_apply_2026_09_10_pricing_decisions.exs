defmodule Sanbase.Repo.Migrations.Apply20260910PricingDecisions do
  use Ecto.Migration

  @moduledoc ~s"""
  The plan-row half of the pricing decisions taken on 2026-09-10 (§8 task **PR**).

  Two rows are taken out of sale, both added by earlier migrations in this epic and
  neither reachable by a customer yet - the whole offering is still held back by
  `is_private` until someone activates it from `/admin/bundle_offering`.

  ## Institutional monthly is withdrawn

  Institutional is sold yearly only. The row is deprecated rather than deleted:
  `plans.is_deprecated` is already checked on both `subscribe` and
  `update_subscription` (`billing_resolver.ex:27` and `:74`), so a deprecated row
  can be neither newly bought nor switched into, while anything already pointing
  at plan id 311 keeps resolving. Deleting it would break those references for no
  gain.

  ## Enterprise stops being a self-serve priced tier

  "Call support, custom pricing" makes Enterprise a negotiated contract, which is
  what `CUSTOM_*` already is. The `ENTERPRISE` row keeps its amount and is simply
  taken out of sale; its clauses in the access checkers stay in place, dead but
  harmless, so restoring a listed price later is an UPDATE rather than a revert.

  ## The price change is deliberately not here

  A Stripe Plan cannot be edited, so moving Institutional to $9,588 means creating a
  new one and pointing the row at it. A migration cannot do that: it would have to
  either write the new amount while the row still points at a Stripe Plan charging the
  old one, or clear `stripe_id` and leave a priced, purchasable row with no Stripe
  object behind it. Both are states a deploy can stop halfway through.

  So the amount is moved by `Sanbase.Billing.switch_institutional_yearly_price/0`,
  which creates the replacement first and only then updates the row - run it after this
  migration. This file changes nothing but the three sale flags, which are plain data.
  """

  @institutional_monthly_plan_id 311
  @enterprise_yearly_plan_id 313

  def up do
    execute("""
    UPDATE plans SET is_deprecated = true
    WHERE id = #{@institutional_monthly_plan_id} AND name = 'INSTITUTIONAL'
    """)

    execute("""
    UPDATE plans SET is_deprecated = true
    WHERE id = #{@enterprise_yearly_plan_id} AND name = 'ENTERPRISE'
    """)
  end

  def down do
    execute("""
    UPDATE plans SET is_deprecated = false
    WHERE id IN (#{@institutional_monthly_plan_id}, #{@enterprise_yearly_plan_id})
    """)
  end
end
