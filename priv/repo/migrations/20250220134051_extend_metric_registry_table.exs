defmodule Sanbase.Repo.Migrations.ExtendMetricRegistryTable do
  use Ecto.Migration

  def change do
    alter table(:metric_registry) do
      add(:last_sync_datetime, :utc_datetime)
    end
  end
end
