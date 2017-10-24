defmodule Sanbase.Repo.Migrations.CreateWhitepapers do
  use Ecto.Migration

  def change do
    create table(:whitepapers) do
      add :project_id, references(:project, on_delete: :delete_all), null: false
      add :link, :string
      add :authors, :integer
      add :pages, :integer
      add :citations, :integer
    end

    create unique_index(:whitepapers, [:project_id])

  end
end
