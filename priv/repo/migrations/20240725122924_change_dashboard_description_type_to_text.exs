defmodule Sanbase.Repo.Migrations.ChangeDashboardDescriptionTypeToText do
  use Ecto.Migration

  def change do
    alter table(:dashboards) do
      modify(:description, :text)
    end
  end
end
