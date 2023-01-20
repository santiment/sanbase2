defmodule Sanbase.Repo.Migrations.CreateSubscriptionTimeseries do
  use Ecto.Migration

  def change do
    create table(:subscription_timeseries) do
      add(:subscriptions, {:array, :map})
      add(:stats, :map)

      timestamps()
    end
  end
end
