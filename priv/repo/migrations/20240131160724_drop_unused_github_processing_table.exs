defmodule Sanbase.Repo.Migrations.DropUnusedGithubProcessingTable do
  @moduledoc false
  use Ecto.Migration

  def up do
    drop_if_exists(table(:processed_github_archives))
  end

  def down do
    # This table is unused for a long time. Its purpose and work has been moved
    # to the github-exporter project
    create table(:processed_github_archives) do
      add(:project_id, references(:project, on_delete: :delete_all))
      add(:archive, :string, null: false)

      timestamps()
    end

    create(unique_index(:processed_github_archives, [:project_id, :archive]))
  end
end
