defmodule Sanbase.Repo.Migrations.CreateCountries do
  use Ecto.Migration

  def change do
    create table(:countries) do
      add :code, :string, null: false
      add :eastern, :boolean
      add :western, :boolean
      add :orthodox, :boolean
      add :sinic, :boolean
    end

    create unique_index(:countries, [:code])
  end
end
