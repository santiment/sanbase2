defmodule Sanbase.Repo.Migrations.CreateInfrastructures do
  use Ecto.Migration

  def change do
    create table(:infrastructures, primary_key: false) do
      add :code, :text, primary_key: true
    end

  end
end
