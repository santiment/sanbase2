defmodule Sanbase.Repo.Migrations.CreateInfrastructures do
  use Ecto.Migration

  def change do
    create table(:infrastructures) do
      add :code, :string, unique: true
    end

  end
end
