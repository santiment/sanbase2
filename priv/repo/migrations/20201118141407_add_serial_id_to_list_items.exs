defmodule Sanbase.Repo.Migrations.AddSerialIdToListItems do
  @moduledoc false
  use Ecto.Migration

  @table :list_items
  def up do
    execute("ALTER TABLE #{@table} DROP CONSTRAINT IF EXISTS list_items_pkey")

    alter table(@table) do
      add(:id, :serial, primary_key: true)
    end
  end

  def down do
    alter table(@table) do
      remove(:id)
    end
  end
end
