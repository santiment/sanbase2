defmodule Sanbase.Repo.Migrations.AddVersionScopeToMetricRegistry do
  use Ecto.Migration

  def change() do
    alter table(:metric_registry) do
      add(:version_scope, :string, null: false, default: "global")
    end
  end
end
