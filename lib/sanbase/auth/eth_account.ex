defmodule Sanbase.Auth.EthAccount do
  use Ecto.Schema
  import Ecto.Changeset

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
  end

  def san_balance(%EthAccount{address: address}) do
    case ethauth().san_balance(address) do
      {:ok, san_balance} ->
        san_balance

      {:error, error} ->
        Logger.error(error)

        nil
    end
  end
end
