defmodule Sanbase.Repo.Migrations.CreateProject do
  use Ecto.Migration

  def change do
    create table(:project) do
      add :name, :string, null: false
      add :ticker, :string, null: false
      add :logo_url, :string
      add :coinmarketcap_id, :string, null: false
    end

    create unique_index(:project, [:name])
    create unique_index(:project, [:coinmarketcap_id])
  end
end
