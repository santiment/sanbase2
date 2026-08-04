defmodule Sanbase.Repo.Migrations.AddStatusToMetricUiMetadata do
  use Ecto.Migration

  def change do
    alter table(:metric_ui_metadata) do
      add(:status, :string, default: "live", null: false)
    end
  end
end
