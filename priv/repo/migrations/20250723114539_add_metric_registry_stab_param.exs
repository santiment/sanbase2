defmodule Sanbase.Repo.Migrations.AddMetricRegistryStabParam do
  use Ecto.Migration

  def change do
    alter table(:metric_registry) do
      add(:stability_period, :string, null: true)
      add(:is_mutable, :boolean, null: true)
    end
  end
end
