defmodule Sanbase.Repo.Migrations.AddSerialIdToListItems do
  use Ecto.Migration

  @table :list_items
  def change do
    execute("ALTER TABLE #{@table} DROP CONSTRAINT list_items_pkey")

    alter table(@table) do
      add(:id, :serial, primary_key: true)
    end
  end
end
