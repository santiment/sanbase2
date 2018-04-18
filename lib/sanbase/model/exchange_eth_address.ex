defmodule Sanbase.Model.ExchangeEthAddress do
  use Ecto.Schema
  import Ecto.Changeset
  alias Sanbase.Model.ExchangeEthAddress

  schema "exchange_eth_addresses" do
    field(:address, :string)
    field(:name, :string)
    field(:source, :string)
    field(:comments, :string)
  end

  @doc false
  def changeset(%ExchangeEthAddress{} = exchange_eth_address, attrs \\ %{}) do
    exchange_eth_address
    |> cast(attrs, [:address, :name, :source, :comments])
    |> validate_required([:address, :name])
    |> unique_constraint(:address)
  end
end
