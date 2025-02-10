defmodule Sanbase.Repo.Migrations.AddImageWidgetsDashboardsField do
  @moduledoc false
  use Ecto.Migration

  def change do
    alter table(:dashboards) do
      add(:image_widgets, :jsonb)
    end
  end
end
