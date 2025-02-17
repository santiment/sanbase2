defmodule Sanbase.Repo.Migrations.AddStatusToMetricRegistry do
  use Ecto.Migration

  def change do
    alter table(:metric_registry) do
      add(:status, :string, null: false, default: "released")
    end
  end
end
