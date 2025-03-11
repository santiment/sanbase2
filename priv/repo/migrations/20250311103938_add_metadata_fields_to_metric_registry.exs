defmodule Sanbase.Repo.Migrations.AddMetadataFieldsToMetricRegistry do
  use Ecto.Migration

  def change do
    alter table(:metric_registry) do
      add(:category, :string)
      add(:group, :string, default: "")
      add(:label, :string)
      add(:style, :string, default: "line")
      add(:format, :string, default: "")
      add(:description, :text)
    end

    # Create an index on category and group for faster lookups
    create(index(:metric_registry, [:category, :group]))
  end
end
