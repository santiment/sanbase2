defmodule Sanbase.Repo.Migrations.CreateDatetimeIndexTimelineEvents do
  @moduledoc false
  use Ecto.Migration

  def change do
    create(index(:timeline_events, [:inserted_at]))
  end
end
