defmodule Sanbase.Repo.Migrations.CreateAvailableMetricsTable do
  use Ecto.Migration

  def change do
    create table(:available_metrics_data) do
      add(:metric, :string, null: false)
      add(:available_slugs, {:array, :string})

      timestamps()
    end

    create(unique_index(:available_metrics_data, [:metric]))
  end
end
