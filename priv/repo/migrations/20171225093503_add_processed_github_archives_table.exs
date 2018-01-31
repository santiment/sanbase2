defmodule Sanbase.Repo.Migrations.AddProcessedGithubArchivesTable do
  use Ecto.Migration

  def change do
    create table(:processed_github_archives) do
      add(:project_id, references(:project, on_delete: :delete_all))
      add(:archive, :string, null: false)

      timestamps()
    end

    create(unique_index(:processed_github_archives, [:project_id, :archive]))
  end
end
