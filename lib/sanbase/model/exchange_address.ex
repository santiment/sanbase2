defmodule Sanbase.Model.ExchangeAddress do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  alias __MODULE__
  alias Sanbase.Repo
  alias Sanbase.Model.Infrastructure

  schema "exchange_addresses" do
    field(:address, :string)
    field(:name, :string)
    field(:source, :string)
    field(:comments, :string)
    field(:csv, :string, virtual: true)
    field(:is_dex, :boolean)

    belongs_to(:infrastructure, Infrastructure)
  end

  @doc false
  def changeset(%ExchangeAddress{} = exchange_address, attrs \\ %{}) do
    exchange_address
    |> cast(attrs, [:address, :name, :source, :comments, :is_dex, :infrastructure_id])
    |> validate_required([:address, :name])
    |> unique_constraint(:address)
  end

  def list_all() do
    Repo.all(__MODULE__)
    |> Enum.map(fn %__MODULE__{address: address} -> address end)
  end

  def list_all_exchanges() do
    from(e in __MODULE__,
      select: e.name,
      distinct: true
    )
    |> Repo.all()
  end

  def addresses_for_exchange(exchange) do
    from(e in __MODULE__,
      where: e.name == ^exchange,
      select: e.address
    )
    |> Repo.all()
    |> case do
      [] -> {:error, "No addresses found for exchange"}
      result -> {:ok, result}
    end
  end
end
