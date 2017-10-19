defmodule Sanbase.Repo.Migrations.CreateProject do
  use Ecto.Migration

  def change do
    create table(:project) do
      add :name, :text, null: false
      add :ticker, :text, null: false
      add :logo_url, :text
      add :coinmarketcap_id, :text, null: false
    end

    create unique_index(:project, [:name])
    create unique_index(:project, [:coinmarketcap_id])
  end
end
