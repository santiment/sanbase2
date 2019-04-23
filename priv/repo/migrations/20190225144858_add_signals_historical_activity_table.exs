defmodule Sanbase.Repo.Migrations.AddHistoricalActivitysTable do
  use Ecto.Migration

  @table "signals_historical_activity"
  def change do
    create table(@table) do
      add(:user_id, references("users"), null: false)
      add(:user_trigger_id, references("user_triggers"), null: false)
      add(:payload, :jsonb, null: false)
      add(:triggered_at, :naive_datetime, null: false)
    end

    create(index(@table, [:user_id, :triggered_at]))
  end
end
