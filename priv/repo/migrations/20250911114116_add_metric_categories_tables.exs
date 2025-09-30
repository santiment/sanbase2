defmodule Sanbase.Repo.Migrations.AddMetricCategoriesTables do
  use Ecto.Migration

  def change do
    # Create categories
    create table(:metric_categories) do
      add(:name, :string, null: false)
      add(:short_description, :text)
      add(:description, :text)

      add(:display_order, :integer)

      timestamps()
    end

    create(unique_index(:metric_categories, [:name]))

    # Create groups
    create table(:metric_groups) do
      add(:name, :string, null: false)
      add(:short_description, :text)
      add(:description, :text)

      add(:display_order, :integer)

      # A group belongs to a category
      add(:category_id, references(:metric_categories, on_delete: :delete_all), null: false)

      timestamps()
    end

    create(unique_index(:metric_groups, [:name]))

    # Create mappings
    create table(:metric_category_mappings) do
      # There's a check constraint that allows either metric_registry_id to be set or module/metric,
      # but not both
      add(:metric_registry_id, references(:metric_registry))

      # There's a check constraint that allows either metric_registry_id to be set or module/metric,
      # but not both
      add(:module, :string)
      add(:metric, :string)

      add(:category_id, references(:metric_categories, on_delete: :delete_all), null: false)
      add(:group_id, references(:metric_groups, on_delete: :delete_all), null: true)

      timestamps()
    end

    # Create a check constraint that either metric_registry_id is set and module/metric are NULL
    # or metric_registry_id is NULL and module/metric are not NULL
    create(
      constraint(:metric_category_mappings, :only_one_metric_identifier,
        check: """
        (metric_registry_id IS NOT NULL AND module IS NULL AND metric IS NULL)
        OR
        (metric_registry_id IS NULL AND module IS NOT NULL AND metric IS NOT NULL)
        """
      )
    )

    # partial unique index
    create(
      index(:metric_category_mappings, [:metric_registry_id],
        unique: true,
        where: "metric_registry_id IS NOT NULL"
      )
    )

    # partial unique index
    create(
      index(:metric_category_mappings, [:module, :metric],
        unique: true,
        where: "module IS NOT NULL AND metric IS NOT NULL"
      )
    )
  end
end
