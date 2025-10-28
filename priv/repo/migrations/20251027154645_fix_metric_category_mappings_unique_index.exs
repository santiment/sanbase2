defmodule Sanbase.Repo.Migrations.FixMetricCategoryMappingsUniqueIndex do
  use Ecto.Migration

  def change do
    drop(unique_index(:metric_category_mappings, [:metric_registry_id, :category_id, :group_id]))
    drop(unique_index(:metric_category_mappings, [:module, :metric, :category_id, :group_id]))

    # partial unique index
    create(
      index(:metric_category_mappings, [:metric_registry_id, :category_id, :group_id],
        unique: true,
        # So if group_id is NULL, the rows are considered the same,
        # group_id null means ungrouped
        nulls_distinct: false,
        where: "metric_registry_id IS NOT NULL"
      )
    )

    # partial unique index
    create(
      index(:metric_category_mappings, [:module, :metric, :category_id, :group_id],
        unique: true,
        # So if group_id is NULL, the rows are considered the same
        # group_id null means ungrouped
        nulls_distinct: false,
        where: "module IS NOT NULL AND metric IS NOT NULL"
      )
    )
  end
end
