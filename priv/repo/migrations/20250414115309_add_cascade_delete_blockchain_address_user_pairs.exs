defmodule Sanbase.Repo.Migrations.AddCascadeDeleteBlockchainAddressUserPairs do
  use Ecto.Migration

  def up do
    drop(constraint(:blockchain_address_user_pairs, "blockchain_address_user_pairs_user_id_fkey"))

    alter table(:blockchain_address_user_pairs) do
      modify(:user_id, references(:users, on_delete: :delete_all))
    end
  end

  def down do
    :ok
  end
end
