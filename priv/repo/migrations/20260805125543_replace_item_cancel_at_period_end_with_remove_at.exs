defmodule Sanbase.Repo.Migrations.ReplaceItemCancelAtPeriodEndWithRemoveAt do
  @moduledoc ~s"""
  Replace the `cancel_at_period_end` boolean on subscription items with the
  moment the item is due to go away.

  A boolean cannot say *which* period end was meant. A subscription's
  `current_period_end` moves forward the instant Stripe renews it, so a job
  looking for "items on subscriptions whose period has ended" finds nothing once
  the renewal is synced - and the item is then billed forever. A deadline stored
  on the item is unaffected by anything the subscription does afterwards.

  Nothing is migrated across. The boolean was added days ago on this same
  unreleased branch and no row anywhere has it set.
  """

  use Ecto.Migration

  def change do
    alter table(:subscription_items) do
      add(:remove_at, :utc_datetime, null: true)
      remove(:cancel_at_period_end, :boolean, null: false, default: false)
    end

    create(index(:subscription_items, [:remove_at]))
  end
end
