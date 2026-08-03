defmodule Sanbase.Repo.Migrations.AddBundlePackageSnapshots do
  use Ecto.Migration

  @moduledoc ~s"""
  A published, frozen answer to "which metrics does each package contain?".

  Categorization is edited continuously by admins in the categorization admin
  screen. If bundle access read that live, moving one metric between categories
  would grant or revoke something a customer paid for - a billing change made
  through a UI that does not look like one. Each bundle subscription pins the
  snapshot version it was resolved against instead.

  See task PD in docs/composable-api-plans-handover.md.
  """

  def up do
    create table(:bundle_package_snapshots) do
      add(:version, :integer, null: false)
      add(:contents, :jsonb, null: false)
      add(:notes, :text)
      add(:published_at, :utc_datetime, null: false)

      timestamps()
    end

    create(unique_index(:bundle_package_snapshots, [:version]))
  end

  def down do
    drop(table(:bundle_package_snapshots))
  end
end
