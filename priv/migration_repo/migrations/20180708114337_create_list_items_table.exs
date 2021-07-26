defmodule Sanbase.Repo.Migrations.CreateListItemsTable do
  use Ecto.Migration

  @table_name :list_items
  def up do
    create table(@table_name, primary_key: false) do
      add(:user_list_id, references(:user_lists, on_delete: :delete_all), primary_key: true)
      add(:project_id, references(:project), null: false, primary_key: true)
    end
  end

  def down do
    drop(table(@table_name))
  end
end
