defmodule Sanbase.Repo.Migrations.AddEthAccountsUserFkCascadeDelete do
  use Ecto.Migration

  def up do
    drop(constraint(:eth_accounts, "eth_accounts_user_id_fkey"))

    alter table(:eth_accounts) do
      modify(:user_id, references(:users, on_delete: :delete_all), null: false)
    end
  end

  def down do
    drop(constraint(:eth_accounts, "eth_accounts_user_id_fkey"))

    alter table(:eth_accounts) do
      modify(:user_id, references(:users), null: false, on_delete: :delete_all)
    end
  end
end
