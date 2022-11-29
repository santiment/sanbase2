defmodule Sanbase.Repo.Migrations.RemoveSanQueryIdFromTables do
  use Ecto.Migration

  def change do
    alter table(:clickhouse_query_executions) do
      remove(:san_query_id)
    end
  end
end
