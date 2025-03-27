defmodule Sanbase.Repo.Migrations.AddUiKeyToMetricDisplayOrder do
  use Ecto.Migration

  def change do
    alter table(:metric_display_order) do
      add(:ui_key, :string)
    end
  end
end
