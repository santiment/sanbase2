defmodule Sanbase.Repo.Migrations.AddSlugSourceMapTable do
  @moduledoc false
  use Ecto.Migration

  @table "source_slug_mappings"
  def change do
    create table(@table) do
      add(:source, :string, null: false)
      add(:slug, :string, null: false)

      add(:project_id, references(:project, on_delete: :delete_all))
    end

    create(unique_index(@table, [:source, :slug], name: :source_slug_unique_combination))
    create(unique_index(@table, [:source, :project_id], name: :one_mapping_per_source))
  end
end
