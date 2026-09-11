defmodule Sanbase.Repo.Migrations.AddGrantToSubscriptions do
  use Ecto.Migration

  @moduledoc """
  An add-on granted by sales and applied by hand in the admin panel: extra
  monthly API calls, and full history on individual data packages.

  Institutional's allowance and history window are otherwise fixed to the plan
  name, so there is nowhere to record "this customer bought more". This is that
  place. See docs/composable-api-plans-handover.md §8 task GR.

  Lives on the subscription row rather than in its own table for the same reason
  `bundle_entitlement` does (§5.4): the row is already loaded on every
  authenticated request, so a column here costs nothing to read while a separate
  table would cost a join.

  Deliberately not the same column as `bundle_entitlement`. That one is recomputed
  from scratch by `Bundle.Resolver.sync/1` on every `customer.subscription.updated`
  event, and a grant stored inside it would be erased by the next webhook.

  NULL for every subscription without an add-on, which is all of them today.
  """

  def up do
    alter table(:subscriptions) do
      add(:grant, :jsonb, null: true)
    end
  end

  def down do
    alter table(:subscriptions) do
      remove(:grant)
    end
  end
end
