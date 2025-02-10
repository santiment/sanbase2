defmodule Sanbase.Repo.Migrations.AddQueryExecutionsTable do
  @moduledoc false
  use Ecto.Migration

  def change do
    create table(:clickhouse_query_executions) do
      add(:user_id, references(:users, on_delete: :delete_all))

      add(:query_id, :string, null: false)
      add(:clickhouse_query_id, :string, null: false)
      add(:execution_details, :map, null: false)
      add(:credits_cost, :integer, null: false)

      timestamps()
    end
  end
end
