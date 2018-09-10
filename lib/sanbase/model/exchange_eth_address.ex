defmodule Sanbase.Model.ExchangeEthAddress do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  alias __MODULE__

  schema "exchange_eth_addresses" do
    field(:address, :string)
    field(:name, :string)
    field(:source, :string)
    field(:comments, :string)
    field(:csv, :string, virtual: true)
  end

  @doc false
  def changeset(%ExchangeEthAddress{} = exchange_eth_address, attrs \\ %{}) do
    exchange_eth_address
    |> cast(attrs, [:address, :name, :source, :comments])
    |> validate_required([:address, :name])
    |> unique_constraint(:address)
  end

  def list_all() do
    Sanbase.Repo.all(__MODULE__)
    |> Enum.map(fn %__MODULE__{address: address} -> address end)
  end
end
