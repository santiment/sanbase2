defmodule Sanbase.Repo.Migrations.AddQueryIdToQueryExecutions do
  use Ecto.Migration

  def up do
    alter table(:clickhouse_query_executions) do
      remove(:query_id)
    end

    alter table(:clickhouse_query_executions) do
      # When the query gets deleted, nilify the query_id.
      # If :delete_all is chosen, deleting queries can be used
      # as a hack to reduce the credits spent.
      add(:query_id, references(:queries, on_delete: :nilify_all), null: true)
    end

    create(index(:clickhouse_query_executions, [:query_id]))
  end

  def down do
    drop(index(:clickhouse_query_executions, [:query_id]))

    alter table(:clickhouse_query_executions) do
      remove(:query_id)
    end

    alter table(:clickhouse_query_executions) do
      add(:query_id, :string)
    end
  end
end
