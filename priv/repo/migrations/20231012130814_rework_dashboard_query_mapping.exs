defmodule Sanbase.Repo.Migrations.ReworkDashboardQueryMapping do
  use Ecto.Migration

  @table :dashboard_query_mappings
  # def up do
  #   alter table(@table) do
  #     add(:uuid, :uuid, null: false)
  #   end

  #   create(unique_index(@table, [:uuid]))

  #   rename(table(@table), :id, to: :old_primary_id)
  #   rename(table(@table), :uuid, to: :id)

  #   alter table(@table) do
  #     remove(:old_primary_id)

  #     modify(:id, :uuid, null: false, primary_key: true)
  #   end
  # end

  def up do
    drop(table(@table))

    create table(@table, primary_key: false) do
      add(:id, :uuid, primary_key: true)
      add(:dashboard_id, references(:dashboards, on_delete: :delete_all))
      add(:query_id, references(:queries, on_delete: :delete_all))

      add(:settings, :map)

      timestamps()
    end

    create(index(@table, [:dashboard_id]))
    create(index(@table, [:query_id]))
  end

  def down do
    drop(table(@table))

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
