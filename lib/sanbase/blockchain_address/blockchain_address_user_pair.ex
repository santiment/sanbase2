defmodule Sanbase.BlockchainAddress.BlockchainAddressUserPair do
  use Ecto.Schema

  import Ecto.Changeset

  @labels_join_through_table "blockchain_address_users_label_pairs"

  schema "blockchain_address_user_pairs" do
    field(:notes, :string)

    belongs_to(:user, Sanbase.Auth.User)
    belongs_to(:blockchain_address, Sanbase.BlockchainAddress)

    many_to_many(
      :labels,
      Sanbase.BlockchainAddress.BlockchainAddressLabel,
      join_through: @labels_join_through_table,
      join_keys: [blockchain_address_user_pair_id: :id, label_id: :id],
      on_replace: :delete,
      on_delete: :delete_all
    )
  end

  def changeset(%__MODULE__{} = addr, attrs \\ %{}) do
    addr
    |> cast(attrs, [:user_id, :blockchain_address_id, :notes])
    |> validate_required([:user_id, :blockchain_address_id])
  end
end
