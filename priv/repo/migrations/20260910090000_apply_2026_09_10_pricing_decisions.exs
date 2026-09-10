defmodule Sanbase.Repo.Migrations.Apply20260910PricingDecisions do
  use Ecto.Migration

  @moduledoc ~s"""
  The plan-row half of the pricing decisions taken on 2026-09-10 (§8 task **PR**).

  Three changes, all to rows added by earlier migrations in this epic and none of
  them reachable by a customer yet - the whole offering is still held back by
  `is_private` until someone activates it from `/admin/bundle_offering`.

  ## Institutional yearly goes from $9,500 to $9,588

  Exactly twelve times the $799 monthly price, so a year paid up front saves
  nothing. That is deliberate and confirmed, unlike the bundles' two months free.

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

  ## The Stripe side is not done here

  A Stripe Price cannot be edited. Changing Institutional's yearly amount means
  creating a new Price and archiving the old one, which
  `Sanbase.Billing.sync_products_with_stripe/0` does not do on its own - it only
  fills in a missing `stripe_id`. So this migration also clears
  `stripe_id` on the yearly row, which is what makes the next sync mint a Price
  at the new amount instead of leaving the old one attached. Nothing is
  subscribed to it, so no customer is affected.
  """

  @institutional_monthly_plan_id 311
  @institutional_yearly_plan_id 312
  @enterprise_yearly_plan_id 313

  # In cents. 12 x $799.
  @new_yearly_amount 958_800
  @old_yearly_amount 950_000

  def up do
    execute("""
    UPDATE plans
    SET amount = #{@new_yearly_amount}, stripe_id = NULL
    WHERE id = #{@institutional_yearly_plan_id} AND name = 'INSTITUTIONAL'
    """)

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
    UPDATE plans
    SET amount = #{@old_yearly_amount}, stripe_id = NULL
    WHERE id = #{@institutional_yearly_plan_id} AND name = 'INSTITUTIONAL'
    """)

    execute("""
    UPDATE plans SET is_deprecated = false
    WHERE id IN (#{@institutional_monthly_plan_id}, #{@enterprise_yearly_plan_id})
    """)
  end
end
