defmodule Sanbase.Repo.Migrations.NullifyTableConfigOnDelete do
  @moduledoc false
  use Ecto.Migration

  @table :user_lists
  def up do
    drop(constraint(@table, "user_lists_table_configuration_id_fkey"))

    alter table(@table) do
      modify(:table_configuration_id, references(:table_configurations, on_delete: :nilify_all))
    end
  end

  def down do
    drop(constraint(@table, "user_lists_table_configuration_id_fkey"))

    alter table(@table) do
      modify(:table_configuration_id, references(:table_configurations))
    end
  end
end
