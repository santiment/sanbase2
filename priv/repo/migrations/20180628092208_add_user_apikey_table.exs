defmodule Sanbase.Repo.Migrations.AddUserApikeyTable do
  use Ecto.Migration

  @table_name :user_api_key_tokens
  def up do
    create table(@table_name) do
      add(:user_id, references(:users, on_delete: :delete_all))
      add(:token, :string, null: false)

      timestamps()
    end

    create(unique_index(:user_api_key_tokens, [:token]))
  end

  def down do
    drop(table(@table_name))
  end
end
