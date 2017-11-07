defmodule Sanbase.Repo.Migrations.RemoveItemsTable do
  use Ecto.Migration

  def up do
    drop table("items")
  end

  def down do
    create table("items") do
      add :name, :string, null: false

      timestamps()
    end
  end
end
