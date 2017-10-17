defmodule Sanbase.Repo.Migrations.CreateWhitepapers do
  use Ecto.Migration

  def change do
    create table(:whitepapers) do
      add :project_id, references(:project, type: :serial, on_delete: :nothing), null: false
      add :link, :text
      add :authors, :integer
      add :pages, :integer
      add :citations, :integer
      add :score, :integer
    end

    create unique_index(:whitepapers, [:project_id])

  end
end
