defmodule Sanbase.Repo.Migrations.AddInstitutionalPlans do
  use Ecto.Migration

  @moduledoc ~s"""
  The `INSTITUTIONAL` plan rows on SanAPI, one per interval.

  Unlike the `BUNDLE` marker rows added alongside them, these are real priced
  plans: Institutional is a fixed tier bought with one Stripe price through the
  ordinary `subscribe` mutation, not a set of items assembled at checkout. So the
  amounts live here, and `Sanbase.Billing.Plan.type/1` classifies them
  `:standard` - no `subscription_items`, no entitlement blob.

  `is_private` starts `true`, which is what keeps the plan out of sale until
  someone turns the new offering on from `/admin/bundle_offering`. Both rows are
  toggled together with the `BUNDLE` rows by
  `Sanbase.Billing.Plan.SaleControls`, and both are excluded from
  `Sanbase.Billing.Plan.product_with_plans/0` - the pricing page renders the
  Institutional column from its own copy rather than from a plans listing.

  `stripe_id` is left NULL. `Sanbase.Billing.sync_products_with_stripe/0` creates
  the Stripe plan on first run and writes the id back, the same way every other
  plans row gets one.

  Prices are the provisional ones from the product brief and are expected to
  change before launch (see §8 task IN and Q11 in
  docs/composable-api-plans-handover.md). Changing them later is an UPDATE here
  plus a new Stripe price - not a schema change.

  See task IN of docs/composable-api-plans-handover.md.
  """

  # Continuing the block the BUNDLE markers started (301, 302), with a gap left
  # in case more marker rows are needed for the composable side.
  @institutional_monthly_plan_id 311
  @institutional_yearly_plan_id 312

  # In cents. $799 / month, $9,500 / year.
  @monthly_amount 79_900
  @yearly_amount 950_000

  @sanapi_product_id 1

  def up do
    execute("""
    INSERT INTO plans (id, name, product_id, amount, currency, interval, "order", is_private, is_deprecated, has_custom_restrictions)
    SELECT #{@institutional_monthly_plan_id}, 'INSTITUTIONAL', p.id, #{@monthly_amount}, 'USD', 'month', 32, true, false, false
    FROM products p WHERE p.id = #{@sanapi_product_id}
    ON CONFLICT DO NOTHING
    """)

    execute("""
    INSERT INTO plans (id, name, product_id, amount, currency, interval, "order", is_private, is_deprecated, has_custom_restrictions)
    SELECT #{@institutional_yearly_plan_id}, 'INSTITUTIONAL', p.id, #{@yearly_amount}, 'USD', 'year', 33, true, false, false
    FROM products p WHERE p.id = #{@sanapi_product_id}
    ON CONFLICT DO NOTHING
    """)
  end

  def down do
    execute("""
    DELETE FROM plans
    WHERE id IN (#{@institutional_monthly_plan_id}, #{@institutional_yearly_plan_id})
    """)
  end
end
