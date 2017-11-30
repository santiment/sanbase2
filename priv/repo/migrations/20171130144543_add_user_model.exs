defmodule Sanbase.Repo.Migrations.AddUserModel do
  use Ecto.Migration

  def change do
    create table(:users) do
      add :username, :string
      add :email, :string
      add :salt, :string, null: false

      timestamps()
    end

    create table(:eth_accounts) do
      add :user_id, references(:users), null: false, on_delete: :delete_all
      add :address, :string, null: false

      timestamps()
    end

    create unique_index(:users, :email)
    create unique_index(:eth_accounts, :address)
  end
end
