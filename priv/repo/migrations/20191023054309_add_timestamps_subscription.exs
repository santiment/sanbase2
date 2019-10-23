defmodule Sanbase.Repo.Migrations.AddTimestampsSubscription do
  use Ecto.Migration

  def change do
    alter table(:subscriptions) do
      timestamps(null: true)
    end
  end
end
