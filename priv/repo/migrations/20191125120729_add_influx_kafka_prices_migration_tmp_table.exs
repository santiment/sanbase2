defmodule Sanbase.Repo.Migrations.AddInfluxKafkaPricesMigrationTmpTable do
  @moduledoc false
  use Ecto.Migration

  def change do
    create table(:price_migration_tmp) do
      add(:slug, :string, null: false)
      add(:is_migrated, :boolean, default: false)
      add(:progress, :text)

      timestamps()
    end
  end
end
