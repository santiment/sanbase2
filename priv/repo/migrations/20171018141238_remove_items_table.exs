defmodule Sanbase.Repo.Migrations.RemoveItemsTable do
  use Ecto.Migration

  def change do
    drop table("items")
  end
end
