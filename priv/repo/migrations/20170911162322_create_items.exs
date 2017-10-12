defmodule Sanbase.Repo.Migrations.CreateItems do
  use Ecto.Migration

  def change do
    create table("items") do
      add :name, :string, null: false
      
      timestamps()
    end
  end
end
