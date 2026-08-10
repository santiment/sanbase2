defmodule Sanbase.Repo.Migrations.AddEnterprisePlan do
  use Ecto.Migration

  @moduledoc ~s"""
  The `ENTERPRISE` plan row on SanAPI. Yearly only.

  The tier above Institutional: everything Institutional grants, plus unlimited
  history and 300,000 API calls a month. Same shape as Institutional - a fixed
  price bought through the ordinary `subscribe` mutation, classified `:standard` by
  `Sanbase.Billing.Plan.type/1`, no `subscription_items` and no entitlement blob.

  ## Not the `CUSTOM_*` path

  Enterprise and custom were used interchangeably for years, because every
  Enterprise deal used to be a hand-built `CUSTOM_<NAME>` plan with a negotiated
  price - `CUSTOM` itself being a $0 placeholder rung. This row is the opposite of
  that: one published price for a declared set of access. Bespoke contracts still
  exist and are still `CUSTOM_*`.

  This is why `20260810121347_retire_legacy_enterprise_plans.exs` has to run first.
  It frees the `ENTERPRISE` name and makes prefix matching on it safe.

  ## Yearly only

  There is no monthly row. The pricing page quotes a yearly figure and nothing
  else, and an unused monthly row would still be purchasable by plan id. Adding one
  later is an INSERT plus a Stripe price.

  `is_private` starts `true`, which keeps the plan out of sale until someone turns
  the new offering on from `/admin/bundle_offering`. It is toggled together with the
  `BUNDLE` and `INSTITUTIONAL` rows by `Sanbase.Billing.Plan.SaleControls`, and it
  is excluded from `Sanbase.Billing.Plan.product_with_plans/0` for the same reason
  they are - the legacy pricing grid cannot render it.

  `stripe_id` is left NULL. `Sanbase.Billing.sync_products_with_stripe/0` creates
  the Stripe plan on first run and writes the id back.

  See task EP of docs/composable-api-plans-handover.md.
  """

  # Continuing the block the BUNDLE markers (301, 302) and Institutional (311, 312)
  # started.
  @enterprise_yearly_plan_id 313

  # In cents. $19,999 / year.
  @yearly_amount 1_999_900

  @sanapi_product_id 1

  def up do
    execute("""
    INSERT INTO plans (id, name, product_id, amount, currency, interval, "order", is_private, is_deprecated, has_custom_restrictions)
    SELECT #{@enterprise_yearly_plan_id}, 'ENTERPRISE', p.id, #{@yearly_amount}, 'USD', 'year', 34, true, false, false
    FROM products p WHERE p.id = #{@sanapi_product_id}
    ON CONFLICT DO NOTHING
    """)
  end

  # Refuses to delete a row that a subscription points at, rather than dying on the
  # foreign key. After the first sale there is nothing safe to roll back to, so
  # `down` withdraws the plan the same way the legacy rows were withdrawn instead of
  # removing it - see `20260810121347_retire_legacy_enterprise_plans.exs`.
  def down do
    execute("""
    UPDATE plans SET name = 'RETIRED_ENTERPRISE', is_private = true, is_deprecated = true
    WHERE id = #{@enterprise_yearly_plan_id}
      AND name = 'ENTERPRISE'
      AND EXISTS (SELECT 1 FROM subscriptions s WHERE s.plan_id = #{@enterprise_yearly_plan_id})
    """)

    execute("""
    DELETE FROM plans
    WHERE id = #{@enterprise_yearly_plan_id}
      AND name = 'ENTERPRISE'
      AND NOT EXISTS (SELECT 1 FROM subscriptions s WHERE s.plan_id = #{@enterprise_yearly_plan_id})
    """)
  end
end
