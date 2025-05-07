defmodule Sanbase.Repo.Migrations.AddFeatureAccessLevelUserField do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add(:feature_access_level, :string)
    end
  end
end
