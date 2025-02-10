defmodule Sanbase.Repo.Migrations.AddTimelineEventCommentsMapping do
  @moduledoc false
  use Ecto.Migration

  @table :timeline_event_comments_mapping
  def change do
    create(table(@table)) do
      add(:comment_id, references(:comments, on_delete: :delete_all))
      add(:timeline_event_id, references(:timeline_events, on_delete: :delete_all))

      timestamps()
    end

    # A comment belongs to at most one timeline_event.
    # A timeline_event can have many comments (so it's not unique_index)
    create(unique_index(@table, [:comment_id]))
    create(index(@table, [:timeline_event_id]))
  end
end
