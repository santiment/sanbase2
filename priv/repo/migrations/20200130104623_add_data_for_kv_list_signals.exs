defmodule Sanbase.Repo.Migrations.AddDataForKvListAlerts do
  @moduledoc false
  use Ecto.Migration

  def change do
    alter table("signals_historical_activity") do
      add(:data, :jsonb)
      modify(:payload, :jsonb, null: true)
    end

    alter table("timeline_events") do
      add(:data, :jsonb)
      modify(:payload, :jsonb, null: true)
    end
  end
end
