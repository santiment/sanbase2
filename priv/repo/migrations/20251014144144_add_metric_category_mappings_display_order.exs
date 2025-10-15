defmodule Sanbase.Repo.Migrations.AddMetricCategoryMappingsDisplayOrder do
  use Ecto.Migration

  def change do
    alter table(:metric_category_mappings) do
      add(:display_order, :integer)
    end
  end
end
