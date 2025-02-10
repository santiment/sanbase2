defmodule Sanbase.Repo.Migrations.CreateCommentNotifications do
  @moduledoc false
  use Ecto.Migration

  def change do
    create table(:comment_notifications) do
      add(:last_insight_comment_id, :integer)
      add(:last_timeline_event_comment_id, :integer)
      add(:notify_users_map, :map)

      timestamps()
    end
  end
end
