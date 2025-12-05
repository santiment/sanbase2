defmodule Sanbase.Repo.Migrations.CreateInsightCategoryMappingTable do
  use Ecto.Migration

  def change do
    create table(:insight_category_mapping) do
      add(:post_id, references(:posts, on_delete: :delete_all), null: false)
      add(:category_id, references(:insight_categories, on_delete: :delete_all), null: false)
      add(:source, :string, null: false, default: "ai")

      timestamps()
    end

    create(unique_index(:insight_category_mapping, [:post_id, :category_id]))
    create(index(:insight_category_mapping, [:post_id]))
    create(index(:insight_category_mapping, [:category_id]))
    create(index(:insight_category_mapping, [:source]))
  end
end
