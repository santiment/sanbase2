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

  @doc ~s"List all exchange addresses"
  @spec list_all() :: list(%__MODULE__{})
  def list_all() do
    Repo.all(__MODULE__)
  end

  @doc ~s"List all exchange names"
  @spec exchange_names() :: list(String.t())
  def exchange_names() do
    from(e in __MODULE__,
      select: e.name,
      distinct: true
    )
    |> Repo.all()
  end

  @doc ~s"List all addresses that belong to certain exchange"
  @spec addresses_for_exchange(String.t()) :: {:ok, [String.t()]} | {:error, String.t()}
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
