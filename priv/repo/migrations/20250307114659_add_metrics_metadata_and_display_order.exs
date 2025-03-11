defmodule Sanbase.Repo.Migrations.AddMetricsMetadataAndDisplayOrder do
  use Ecto.Migration

  def change do
    create table(:metric_display_order) do
      add(:metric, :string, null: false)
      add(:category, :string, null: false)
      add(:group, :string, default: "")
      add(:display_order, :integer, null: false)
      # "registry" or "code"
      add(:source_type, :string, default: "code")
      # ID reference to registry if applicable
      add(:source_id, :integer)
      add(:added_at, :utc_datetime)
      add(:label, :string)
      add(:style, :string, default: "line")
      add(:format, :string, default: "")
      add(:description, :text)

      timestamps()
    end

    create(unique_index(:metric_display_order, [:metric]))
    create(index(:metric_display_order, [:category, :group, :display_order]))
    create(index(:metric_display_order, [:source_type, :source_id]))
  end
end
