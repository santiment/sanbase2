defmodule Sanbase.Repo.Migrations.ExtendRegistryChangelogTable do
  use Ecto.Migration

  def change do
    alter table(:metric_registry_changelog) do
      add(:change_trigger, :string)
    end
  end
end
