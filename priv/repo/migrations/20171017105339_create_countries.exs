defmodule Sanbase.Repo.Migrations.CreateCountries do
  use Ecto.Migration

  def change do
    create table(:countries, primary_key: false) do
      add :code, :text, primary_key: true
      add :western, :boolean
      add :orthodox, :boolean
      add :sinic, :boolean
    end

  end
end
