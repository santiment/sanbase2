defmodule Sanbase.Repo.Migrations.CreateInfrastructures do
  use Ecto.Migration

  def change do
    create table(:infrastructures) do
      add :code, :string, null: false
    end

    create unique_index(:infrastructures, [:code])
  end
end
