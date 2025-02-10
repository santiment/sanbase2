defmodule Sanbase.Repo.Migrations.AddOnDeleteTimelineEvents do
  @moduledoc false
  use Ecto.Migration

  @table "timeline_events"
  def up do
    drop(constraint(@table, "timeline_events_post_id_fkey"))
    drop(constraint(@table, "timeline_events_user_id_fkey"))
    drop(constraint(@table, "timeline_events_user_list_id_fkey"))
    drop(constraint(@table, "timeline_events_user_trigger_id_fkey"))

    alter table(@table) do
      modify(:user_id, references(:users, on_delete: :delete_all))
      modify(:post_id, references(:posts, on_delete: :delete_all))
      modify(:user_list_id, references(:user_lists, on_delete: :delete_all))
      modify(:user_trigger_id, references(:user_triggers, on_delete: :delete_all))
    end
  end

  def down do
    drop(constraint(@table, "timeline_events_post_id_fkey"))
    drop(constraint(@table, "timeline_events_user_id_fkey"))
    drop(constraint(@table, "timeline_events_user_list_id_fkey"))
    drop(constraint(@table, "timeline_events_user_trigger_id_fkey"))

    alter table(@table) do
      modify(:user_id, references(:users))
      modify(:post_id, references(:posts))
      modify(:user_list_id, references(:user_lists))
      modify(:user_trigger_id, references(:user_triggers))
    end
  end
end
