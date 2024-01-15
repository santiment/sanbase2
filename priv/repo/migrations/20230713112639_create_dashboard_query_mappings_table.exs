defmodule Sanbase.Repo.Migrations.CreateDashboardQueryMappingsTable do
  use Ecto.Migration

  @table :dashboard_query_mappings
  def change do
    create table(@table) do
      add(:dashboard_id, references(:dashboards, on_delete: :delete_all))
      add(:query_id, references(:queries, on_delete: :delete_all))

      add(:settings, :map)

      timestamps()
    end

    create(index(@table, [:dashboard_id]))
    create(index(@table, [:query_id]))
  end
end
