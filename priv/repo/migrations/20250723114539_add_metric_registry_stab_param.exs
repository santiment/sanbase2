defmodule Sanbase.Repo.Migrations.AddMetricRegistryStabParam do
  use Ecto.Migration

  def change do
    alter table(:metric_registry) do
      add(:stabilization_period, :string, null: true)
      add(:can_mutate, :boolean, null: true)
    end
  end
end
