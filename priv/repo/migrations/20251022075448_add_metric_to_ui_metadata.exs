defmodule Sanbase.Repo.Migrations.AddMetricToUiMetadata do
  use Ecto.Migration

  def change do
    alter table(:metric_ui_metadata) do
      add(:metric, :string)
    end
  end
end
