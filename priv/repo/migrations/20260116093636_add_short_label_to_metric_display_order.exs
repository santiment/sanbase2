defmodule Sanbase.Repo.Migrations.AddShortLabelToMetricDisplayOrder do
  use Ecto.Migration

  def change do
    alter table(:metric_display_order) do
      add(:short_label, :string)
    end
  end
end
