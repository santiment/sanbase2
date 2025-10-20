defmodule Sanbase.Repo.Migrations.UpdateUiMetadataForMultiplePerMapping do
  use Ecto.Migration

  def up do
    drop_if_exists(
      index(:metric_ui_metadata, [:metric_category_mapping_id],
        name: :metric_ui_metadata_metric_category_mapping_id_index
      )
    )

    drop_if_exists(unique_index(:metric_ui_metadata, [:metric_category_mapping_id]))
  end

  def down do
    create(unique_index(:metric_ui_metadata, [:metric_category_mapping_id]))
  end
end
