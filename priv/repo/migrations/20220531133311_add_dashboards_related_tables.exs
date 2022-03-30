defmodule Sanbase.Repo.Migrations.AddDashboardsRelatedTables do
  use Ecto.Migration

  def change do
    create table("dashboards") do
      add(:name, :string, null: false)
      add(:description, :string, null: true)
      add(:is_public, :boolean, default: false, null: false)
      add(:panels, :map, null: true, default: nil)

      add(:user_id, references(:users), nill: false, on_delete: :delete_all)

      timestamps()
    end

    create table("dashboards_cache") do
      add(:dashboard_id, references(:dashboards, on_delete: :delete_all))
      add(:panels, :map, null: false)

      timestamps()
    end

    create(unique_index(:dashboards_cache, [:dashboard_id]))
  end
end
