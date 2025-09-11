defmodule Sanbase.Repo.Migrations.AddMetricCategoriesTables do
  use Ecto.Migration

  def change do
    # Create categories
    create table(:metric_categories) do
      add(:name, :string, null: false)
      # ID that won't change and can be used in URLs?
      add(:slug, :string, null: false)
      add(:short_description, :text)
      add(:description, :text)

      add(:display_order, :integer)

      timestamps()
    end

    create(unique_index(:metric_categories, [:name]))
    create(unique_index(:metric_categories, [:slug]))

    # Create groups
    create table(:metric_groups) do
      add(:name, :string, null: false)
      add(:slug, :string, null: false)
      add(:short_description, :text)
      add(:description, :text)

      add(:display_order, :integer)

      # A group belongs to a category
      add(:category_id, references(:metric_categories, on_delete: :delete_all), null: false)

      timestamps()
    end

    create(unique_index(:metric_groups, [:name]))
    create(unique_index(:metric_groups, [:slug]))

    # Create mappings
    create table(:metric_categories_mapping) do
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
      constraint(:metric_categories_mapping, :only_one_metric_identifier,
        check: """
        (metric_registry_id IS NOT NULL AND module IS NULL AND metric IS NULL)
        OR
        (metric_registry_id IS NULL AND module IS NOT NULL AND metric IS NOT NULL)
        """
      )
    )

    # partial unique index
    create(
      index(:metric_categories_mapping, [:metric_registry_id],
        unique: true,
        where: "metric_registry_id IS NOT NULL"
      )
    )

    # partial unique index
    create(
      index(:metric_categories_mapping, [:module, :metric],
        unique: true,
        where: "module IS NOT NULL AND metric IS NOT NULL"
      )
    )
  end
end
