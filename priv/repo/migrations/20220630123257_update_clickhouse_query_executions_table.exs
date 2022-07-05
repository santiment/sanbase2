defmodule Sanbase.Repo.Migrations.UpdateClickhouseQueryExecutionsTable do
  use Ecto.Migration

  def change do
    alter table(:clickhouse_query_executions) do
      add(:san_query_id, :string, null: false)
      add(:query_start_time, :naive_datetime, null: false)
      add(:query_end_time, :naive_datetime, null: false)

      # Make the field nullable as now san_query_id will be used
      # This field will be dropped once the code for using the new
      # field is deployed.
      modify(:query_id, :string, null: true)
    end
  end
end
