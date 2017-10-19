defmodule Sanbase.Repo.Migrations.CreateCountries do
  use Ecto.Migration

  def change do
    create table(:countries) do
      add :code, :text, unique: true
      add :western, :boolean
      add :orthodox, :boolean
      add :sinic, :boolean
    end

  end
end
