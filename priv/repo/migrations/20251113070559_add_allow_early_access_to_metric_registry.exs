defmodule Sanbase.Repo.Migrations.AddAllowEarlyAccessToMetricRegistry do
  use Ecto.Migration

  def change do
    alter table(:metric_registry) do
      add(:allow_early_access, :boolean, default: false, null: false)
    end
  end
end
