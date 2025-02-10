defmodule Sanbase.Repo.Migrations.AddPostgresUserTriggerIndexes do
  @moduledoc false
  use Ecto.Migration

  def change do
    create(index(:timeline_events, [:user_trigger_id]))
    create(index(:signals_historical_activity, [:user_trigger_id]))
  end
end
