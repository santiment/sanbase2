defmodule Sanbase.Repo.Migrations.AddOnDeleteUserEntityInteractions do
  @moduledoc false
  use Ecto.Migration

  @table :user_entity_interactions
  def up do
    drop(constraint(@table, "user_entity_interactions_user_id_fkey"))

    alter table(@table) do
      modify(:user_id, references(:users, on_delete: :delete_all), null: false)
    end
  end

  def down do
    drop(constraint(@table, "user_entity_interactions_user_id_fkey"))

    alter table(@table) do
      modify(:user_id, references(:users), null: false)
    end
  end
end
