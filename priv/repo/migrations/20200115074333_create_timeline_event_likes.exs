defmodule Sanbase.Repo.Migrations.CreateTimelineEventLikes do
  use Ecto.Migration

  def change do
    create table(:timeline_event_likes) do
      add(:timeline_event_id, references(:timeline_events))
      add(:user_id, references(:users))

      timestamps()
    end

    create(unique_index(:timeline_event_likes, [:timeline_event_id, :user_id]))
  end
end
