defmodule Sanbase.Repo.Migrations.AddDryRunSync do
  use Ecto.Migration

  def change do
    alter table(:metric_registry_sync_runs) do
      add(:is_dry_run, :boolean, default: false)
    end
  end
end
