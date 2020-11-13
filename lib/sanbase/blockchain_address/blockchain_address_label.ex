defmodule Sanbase.BlockchainAddress.BlockchainAddressLabel do
  use Ecto.Schema

  import Ecto.Changeset

  schema "blockchain_address_labels" do
    field(:label, :string)
    field(:notes, :string)
  end

  def changeset(%__MODULE__{} = addr, attrs \\ %{}) do
    addr
    |> cast(attrs, [:label, :notes])
    |> validate_required([:label])
  end
end
