defmodule Sanbase.Repo.Migrations.AddIsChartEventToInsights do
  @moduledoc false
  use Ecto.Migration

  def change do
    alter table("posts") do
      add(:is_chart_event, :boolean, default: false)
      add(:chart_event_datetime, :utc_datetime)

      add(
        :chart_configuration_for_event_id,
        references(:chart_configurations),
        null: true
      )
    end
  end
end
