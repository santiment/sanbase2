defmodule Sanbase.Repo.Migrations.AddSlugSourceMapTable do
  use Ecto.Migration

  @table "slug_source_mappings"
  def change do
    create table(@table) do
      add(:source, :string, null: false)
      add(:source_slug, :string, null: false)

      add(:project_id, references(:project, on_delete: :delete_all))
    end

    create(unique_index(@table, [:source, :source_slug], name: :source_slug_unique_combination))
    create(unique_index(@table, [:source, :project_id], name: :one_mapping_per_source))
  end
end
