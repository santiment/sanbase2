defmodule Sanbase.Repo.Migrations.CreateGithubOrganizationsTable do
  @moduledoc false
  use Ecto.Migration

  @table :github_organizations
  def change do
    create table(@table) do
      add(:organization, :string)
      add(:project_id, references(:project, on_delete: :delete_all))
    end

    create(unique_index(@table, [:project_id, :organization]))
  end
end
