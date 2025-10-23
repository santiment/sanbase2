defmodule Sanbase.Repo.Migrations.RemoveUiHumanReadableIndexFromUiMetadata do
  use Ecto.Migration

  def change do
    drop(unique_index(:metric_ui_metadata, [:ui_human_readable_name]))
  end
end
