defmodule Sanbase.Repo.Migrations.CreateGithubOrganizationsSuggestionsTable do
  use Ecto.Migration

  def change do
    create table(:project_github_organizations_change_suggestions) do
      add(:project_id, references(:project, on_delete: :delete_all))
      add(:added_organizations, {:array, :string})
      add(:removed_organizations, {:array, :string})
      add(:notes, :text)

      add(:status, :string, default: "pending_approval")

      timestamps()
    end
  end
end
