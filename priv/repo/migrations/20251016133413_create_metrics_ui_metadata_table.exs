defmodule Sanbase.Repo.Migrations.CreateMetricsUiMetadataTable do
  use Ecto.Migration

  def change do
    create table(:metric_ui_metadata) do
      add(:ui_human_readable_name, :string)
      add(:ui_key, :string)
      add(:chart_style, :string, default: "line")
      add(:unit, :string, default: "")
      add(:args, :map, default: %{})

      add(:show_on_sanbase, :boolean, default: true)

      add(:display_order_in_mapping, :integer)

      add(
        :metric_category_mapping_id,
        references(:metric_category_mappings, on_delete: :delete_all),
        null: false
      )

      timestamps()
    end
  end
end
