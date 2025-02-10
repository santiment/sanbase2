defmodule Sanbase.Repo.Migrations.AddOnDeleteFeaturedItems do
  @moduledoc false
  use Ecto.Migration

  @table "featured_items"

  def up do
    drop(constraint(@table, "featured_items_post_id_fkey"))
    drop(constraint(@table, "featured_items_table_configuration_id_fkey"))
    drop(constraint(@table, "featured_items_chart_configuration_id_fkey"))
    drop(constraint(@table, "featured_items_user_list_id_fkey"))
    drop(constraint(@table, "featured_items_user_trigger_id_fkey"))

    alter table(@table) do
      modify(:post_id, references(:posts, on_delete: :delete_all))
      modify(:user_list_id, references(:user_lists, on_delete: :delete_all))
      modify(:chart_configuration_id, references(:chart_configurations, on_delete: :delete_all))
      modify(:table_configuration_id, references(:table_configurations, on_delete: :delete_all))
      modify(:user_trigger_id, references(:user_triggers, on_delete: :delete_all))
    end
  end

  def down do
    drop(constraint(@table, "featured_items_post_id_fkey"))
    drop(constraint(@table, "featured_items_table_configuration_id_fkey"))
    drop(constraint(@table, "featured_items_chart_configuration_id_fkey"))
    drop(constraint(@table, "featured_items_user_list_id_fkey"))
    drop(constraint(@table, "featured_items_user_trigger_id_fkey"))

    alter table(@table) do
      modify(:post_id, references(:posts))
      modify(:user_list_id, references(:user_lists))
      modify(:chart_configuration_id, references(:chart_configurations))
      modify(:table_configuration_id, references(:table_configurations))
      modify(:user_trigger_id, references(:user_triggers))
    end
  end
end
