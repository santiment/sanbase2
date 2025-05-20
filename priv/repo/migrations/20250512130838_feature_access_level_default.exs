defmodule Sanbase.Repo.Migrations.FeatureAccessLevelDefault do
  use Ecto.Migration

  def up do
    alter table(:users) do
      modify(:feature_access_level, :string, null: false, default: "released")
    end
  end

  def down do
    alter table(:users) do
      modify(:feature_access_level, :string, null: true, default: nil)
    end
  end
end
