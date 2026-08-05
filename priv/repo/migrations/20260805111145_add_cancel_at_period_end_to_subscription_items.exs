defmodule Sanbase.Repo.Migrations.AddCancelAtPeriodEndToSubscriptionItems do
  use Ecto.Migration

  def change do
    alter table(:subscription_items) do
      add(:cancel_at_period_end, :boolean, null: false, default: false)
    end
  end
end
