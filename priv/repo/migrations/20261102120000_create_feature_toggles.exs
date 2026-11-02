defmodule Sanbase.Repo.Migrations.CreateFeatureToggles do
  use Ecto.Migration

  # On/off switches, see Sanbase.FeatureToggle.
  def change() do
    create table(:feature_toggles) do
      add(:name, :string, null: false)
      add(:enabled, :boolean, null: false, default: false)

      timestamps()
    end

    create(unique_index(:feature_toggles, [:name]))
  end
end
