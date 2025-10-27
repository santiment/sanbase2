defmodule Sanbase.Repo.Migrations.ReworkMetricCategoryMappingsUniqueIndex do
  use Ecto.Migration

  def change do
    drop(unique_index(:metric_category_mappings, [:metric_registry_id]))
    drop(unique_index(:metric_category_mappings, [:module, :metric]))

    # partial unique index
    create(
      index(:metric_category_mappings, [:metric_registry_id, :category_id, :group_id],
        unique: true,
        where: "metric_registry_id IS NOT NULL"
      )
    )

    # partial unique index
    create(
      index(:metric_category_mappings, [:module, :metric, :category_id, :group_id],
        unique: true,
        where: "module IS NOT NULL AND metric IS NOT NULL"
      )
    )
  end
end
