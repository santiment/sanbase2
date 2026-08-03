defmodule Sanbase.Repo.Migrations.AddBundleEntitlementToSubscriptions do
  use Ecto.Migration

  @moduledoc """
  Holds the resolved entitlement of a bundle subscription.

  It is resolved once when the subscription's items change and stored here, so
  that answering "what does this customer have access to?" never needs to decode
  items or hit Stripe. See docs/composable-api-plans-handover.md §5.4.

  NULL for every non-bundle subscription, which is every subscription that
  exists today.
  """

  def up do
    alter table(:subscriptions) do
      add(:bundle_entitlement, :jsonb, null: true)
    end
  end

  def down do
    alter table(:subscriptions) do
      remove(:bundle_entitlement)
    end
  end
end
