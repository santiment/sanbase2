defmodule Sanbase.Repo.Migrations.CreateSeenTimelineEvents do
  @moduledoc false
  use Ecto.Migration

  def change do
    create table(:seen_timeline_events) do
      add(:seen_at, :utc_datetime)
      add(:user_id, references(:users, on_delete: :nothing))
      add(:event_id, references(:timeline_events, on_delete: :nothing))

      timestamps()
    end

    create(unique_index(:seen_timeline_events, [:user_id, :event_id]))
  end
end
