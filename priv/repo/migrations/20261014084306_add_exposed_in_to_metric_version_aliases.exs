defmodule Sanbase.Repo.Migrations.AddExposedInToMetricVersionAliases do
  use Ecto.Migration

  # Where a version can be used: "all", "api_only" or "sanbase_only". Every existing
  # version stays available everywhere.
  def change() do
    alter table(:metric_version_aliases) do
      add(:exposed_in, :string, null: false, default: "all")
    end
  end
end
