defmodule Sanbase.BlockchainAddress do
  use Ecto.Schema

  import Ecto.Changeset

  alias Sanbase.Model.Infrastructure

  schema "blockchain_addresses" do
    field(:address, :string)
    field(:notes, :string)

    belongs_to(:infrastructure, Infrastructure)
  end

  def changeset(%__MODULE__{} = addr, attrs \\ %{}) do
    addr
    |> cast(attrs, [:address, :infrastructure_id, :notes])
    |> validate_required([:address])
  end
end
