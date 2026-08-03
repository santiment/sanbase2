defmodule Sanbase.Repo.Migrations.AddBundleSubscriptionItemsAndPrices do
  use Ecto.Migration

  @moduledoc ~s"""
  What a bundle customer bought, and what the things they can buy cost.

  Three parts:

    * `subscription_items` - one row per purchased line item. A bundle
      subscription is one Stripe subscription with many items, so
      `subscriptions.plan_id` alone cannot say what was bought.

    * `bundle_prices` - the local catalog of sellable items. Deliberately not
      `plans` rows: a `plans` row is a whole subscription tier, and treating
      per-item prices as plans is what makes the existing upgrade/downgrade code
      misbehave on multi-item subscriptions.

    * the `BUNDLE` marker plan rows on SanAPI, one per interval. Amount 0,
      because the real amounts live per item in the catalog.

  Legacy subscriptions get no `subscription_items` rows, which is how the code
  tells them apart from bundles without consulting Stripe.

  See task LC and §5.7 of docs/composable-api-plans-handover.md.
  """

  # Outside both existing ranges (SanAPI uses 1-9 and 101-110, Sanbase 11 and
  # 201-211) so these can be inserted with fixed ids like every other plan.
  @bundle_monthly_plan_id 301
  @bundle_yearly_plan_id 302

  def up do
    create table(:subscription_items) do
      add(:subscription_id, references(:subscriptions, on_delete: :delete_all), null: false)

      # NULL until the item exists in Stripe. Items can be seeded locally so
      # that everything downstream is testable before any Stripe object exists.
      add(:stripe_item_id, :string)

      add(:sku, :string, null: false)
      add(:type, :string, null: false)
      add(:quantity, :integer, null: false, default: 1)

      timestamps()
    end

    create(unique_index(:subscription_items, [:stripe_item_id]))

    # A package is either bought or not; buying more of the same add-on is a
    # quantity, not a second row. This also makes the resolver's union
    # unambiguous.
    create(unique_index(:subscription_items, [:subscription_id, :sku]))

    create table(:bundle_prices) do
      add(:sku, :string, null: false)
      add(:type, :string, null: false)
      add(:interval, :string, null: false)

      add(:stripe_price_id, :string)

      # NULL is meaningful: the item is known and sellable in principle, but its
      # price has not been decided yet. Stripe Prices are immutable, so a price
      # change is a new row plus deactivating the old one, never an update.
      add(:amount, :integer)
      add(:currency, :string, null: false, default: "USD")
      add(:is_active, :boolean, null: false, default: true)

      timestamps()
    end

    create(unique_index(:bundle_prices, [:sku, :interval, :is_active], where: "is_active"))
    create(unique_index(:bundle_prices, [:stripe_price_id]))

    # Selected from `products` rather than inserted with a literal product_id so
    # this is a no-op where products have not been seeded yet - a fresh database
    # gets its plans from priv/repo/seed_plans_and_products.exs, which also
    # carries these two rows, and would otherwise fail the foreign key here.
    execute("""
    INSERT INTO plans (id, name, product_id, amount, currency, interval, "order", is_private, is_deprecated, has_custom_restrictions)
    SELECT #{@bundle_monthly_plan_id}, 'BUNDLE', p.id, 0, 'USD', 'month', 30, true, false, false
    FROM products p WHERE p.id = 1
    ON CONFLICT DO NOTHING
    """)

    execute("""
    INSERT INTO plans (id, name, product_id, amount, currency, interval, "order", is_private, is_deprecated, has_custom_restrictions)
    SELECT #{@bundle_yearly_plan_id}, 'BUNDLE', p.id, 0, 'USD', 'year', 31, true, false, false
    FROM products p WHERE p.id = 1
    ON CONFLICT DO NOTHING
    """)
  end

  def down do
    execute(
      "DELETE FROM plans WHERE id IN (#{@bundle_monthly_plan_id}, #{@bundle_yearly_plan_id})"
    )

    drop(table(:bundle_prices))
    drop(table(:subscription_items))
  end
end
