defmodule Sanbase.Repo.Migrations.CreateExchangesTable do
  use Ecto.Migration

  def up do
    create table(:exchanges) do
      add(:name, :string, null: false)
    end

    create(unique_index(:exchanges, :name))

    execute("INSERT INTO exchanges (name) (SELECT DISTINCT name FROM exchange_addresses)")
  end

  def down do
    drop(table(:exchanges))
  end
end
