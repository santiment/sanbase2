defmodule Sanbase.Model.ExchangeEthAddress do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  alias __MODULE__
  alias Sanbase.Repo
  alias Sanbase.Model.Infrastructure

  schema "exchange_eth_addresses" do
    field(:address, :string)
    field(:name, :string)
    field(:source, :string)
    field(:comments, :string)
    field(:csv, :string, virtual: true)
    field(:is_dex, :boolean)

    belongs_to(:infrastructure, Infrastructure)
  end

  @doc false
  def changeset(%ExchangeEthAddress{} = exchange_eth_address, attrs \\ %{}) do
    exchange_eth_address
    |> cast(attrs, [:address, :name, :source, :comments, :is_dex, :infrastructure_id])
    |> validate_required([:address, :name])
    |> unique_constraint(:address)
  end

  def list_all() do
    Repo.all(__MODULE__)
    |> Enum.map(fn %__MODULE__{address: address} -> address end)
  end
end
