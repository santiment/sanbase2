defmodule Sanbase.Repo.Migrations.AddNewFieldsSubscription do
  use Ecto.Migration

  def change do
    alter table(:subscriptions) do
      add(:active, :boolean, null: false, default: false)
      add(:cancel_at_period_end, :boolean, null: false, default: false)
      add(:current_period_end, :utc_datetime)
    end
  end
end
