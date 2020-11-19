defmodule Sanbase.Repo.Migrations.AddUserBlockchainAddresses do
  use Ecto.Migration

  def change do
    create table(:blockchain_address_user_pairs) do
      add(:notes, :string)
      add(:user_id, references(:users))
      add(:blockchain_address_id, references(:blockchain_addresses))
    end

    blockchain_address_user_pairs_labels

    create table(:blockchain_address_users_label_pairs) do
      add(:blockchain_address_user_pair_id, references(:blockchain_address_user_pairs))
      add(:label_id, references(:blockchain_address_labels))
    end
  end
end
