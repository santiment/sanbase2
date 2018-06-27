defmodule Sanbase.Repo.Migrations.AddUserApikeyTable do
  use Ecto.Migration

  def change do
    create table(:user_api_key_tokens) do
      add(:user_id, references(:users, on_delete: :delete_all))
      add(:token, :string, null: false)

      timestamps()
    end

    create(unique_index(:user_api_key_tokens, [:token]))
  end
end
