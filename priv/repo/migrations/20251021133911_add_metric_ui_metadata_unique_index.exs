defmodule Sanbase.Repo.Migrations.AddMetricUiMetadataUniqueIndex do
  use Ecto.Migration

  def change do
    create(unique_index(:metric_ui_metadata, [:ui_key]))
    create(unique_index(:metric_ui_metadata, [:ui_human_readable_name]))
  end
end
