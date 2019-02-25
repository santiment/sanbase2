defmodule Sanbase.Repo.Migrations.AddUserSignalsTable do
  use Ecto.Migration

  @table "user_signals"
  def change do
    create table(@table) do
      add(:user_id, references("users"), null: false)
      add(:user_trigger_id, references("user_triggers"), null: false)
      add(:payload, :jsonb)

      timestamps()
    end

    create(index(@table, [:user_id]))
  end
end
