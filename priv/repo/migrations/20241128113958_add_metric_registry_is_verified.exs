defmodule Sanbase.Repo.Migrations.AddMetricRegistryIsVerified do
  use Ecto.Migration

  def change do
    alter table(:metric_registry) do
      add(:is_verified, :boolean, null: false, default: true)
      add(:sync_status, :string, null: false, default: "synced")
    end
  end
end
