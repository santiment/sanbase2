defmodule Sanbase.Repo.Migrations.AddStatusToMetricDisplayOrder do
  use Ecto.Migration

  def change do
    alter table(:metric_display_order) do
      add(:status, :string, default: "live", null: false)
    end
  end
end
