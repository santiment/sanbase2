defmodule Sanbase.Repo.Migrations.AddMetricUiMetadataUniqueIndexMetricArgs do
  use Ecto.Migration

  def change do
    create(
      unique_index(:metric_ui_metadata, [:metric, :args],
        name: :metric_ui_metadata_metric_args_index
      )
    )
  end
end
