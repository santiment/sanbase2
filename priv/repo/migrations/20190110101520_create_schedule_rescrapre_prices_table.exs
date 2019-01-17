defmodule Sanbase.Repo.Migrations.CreateScheduleRescraprePricesTable do
  use Ecto.Migration

  def change do
    create table("schedule_rescrape_prices") do
      add(:project_id, references(:project), null: false)
      add(:from, :naive_datetime, null: false)
      add(:to, :naive_datetime, null: false)
      add(:original_last_updated, :naive_datetime)
      add(:in_progress, :boolean, null: false)
      add(:finished, :boolean, null: false)
      timestamps()
    end

    create(index("schedule_rescrape_prices", [:project_id]))
  end
end
