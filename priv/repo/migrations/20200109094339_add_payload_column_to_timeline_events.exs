defmodule Sanbase.Repo.Migrations.AddPayloadColumnToTimelineEvents do
  @moduledoc false
  use Ecto.Migration

  def change do
    alter table(:timeline_events) do
      add(:payload, :jsonb, null: true)
    end
  end
end
