defmodule Sanbase.Repo.Migrations.CreateMetricDisplayOrder do
  use Ecto.Migration

  def change do
    create table(:metric_display_order) do
      add(:metric, :string, null: true)
      add(:registry_metric, :string, null: true)
      add(:args, :map, default: "{}")
      add(:category_id, references(:ui_metadata_categories, on_delete: :delete_all), null: false)
      add(:group_id, references(:ui_metadata_groups, on_delete: :delete_all), null: true)
      add(:display_order, :integer, null: false)
      add(:source_type, :string, default: "code")
      add(:code_module, :string)
      add(:metric_registry_id, references(:metric_registry, on_delete: :delete_all), null: true)
      add(:ui_human_readable_name, :string)
      add(:chart_style, :string, default: "line")
      add(:unit, :string, default: "")
      add(:description, :text)

      timestamps()
    end
  end
end
