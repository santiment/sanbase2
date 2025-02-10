defmodule Sanbase.Repo.Migrations.AddUserBlockchainAddresses do
  @moduledoc false
  use Ecto.Migration

  def change do
    create table(:blockchain_address_user_pairs) do
      add(:notes, :string)
      add(:user_id, references(:users))
      add(:blockchain_address_id, references(:blockchain_addresses))
    end

    create(unique_index(:blockchain_address_user_pairs, [:user_id, :blockchain_address_id]))

    create table(:blockchain_address_user_pairs_labels) do
      add(:blockchain_address_user_pair_id, references(:blockchain_address_user_pairs))
      add(:label_id, references(:blockchain_address_labels))
    end

    create(
      unique_index(:blockchain_address_user_pairs_labels, [
        :blockchain_address_user_pair_id,
        :label_id
      ])
    )
  end
end
