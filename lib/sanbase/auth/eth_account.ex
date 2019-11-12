defmodule Sanbase.Auth.EthAccount do
  use Ecto.Schema
  import Ecto.Changeset

  alias Sanbase.Repo
  alias Sanbase.Auth.{User, EthAccount}

  require Logger
  require Mockery.Macro

  defp ethauth, do: Mockery.Macro.mockable(Sanbase.InternalServices.Ethauth)

  schema "eth_accounts" do
    field(:address, :string)
    belongs_to(:user, User)

    timestamps()
  end

  def changeset(%EthAccount{} = eth_account, attrs \\ %{}) do
    eth_account
    |> cast(attrs, [
      :address,
      :user_id
    ])
    |> unique_constraint(:address)
  end

  def create(attrs) do
    %__MODULE__{}
    |> changeset(attrs)
    |> Repo.insert()
  end

  def by_address(address) do
    Repo.get_by(__MODULE__, address: address)
  end

  def san_balance(%EthAccount{address: address}) do
    case ethauth().san_balance(address) do
      {:ok, san_balance} ->
        san_balance

      {:error, error} ->
        Logger.error(error)

        :error
    end
  end
end
