defmodule Sanbase.Repo.Migrations.CreateQueriesCacheTable do
  use Ecto.Migration

  @table :dashboards_cache
  def change do
    create table(@table) do
      add(:query_id, references(:queries, on_delete: :delete_all), nil: false)
      add(:user_id, references(:users, on_delete: :delete_all), nil: false)
      add(:data, :map, nil: false)
      add(:query_hash, :text, nil: false)

      timestamps()
    end

    create(unique_index(@table, [:query_id, :user_id]))
  end
end
