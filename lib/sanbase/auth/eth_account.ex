defmodule Sanbase.Auth.EthAccount do
  use Ecto.Schema

  alias Sanbase.Auth.User
  alias Sanbase.Auth.Ethauth

  schema "eth_accounts" do
    field :address, :string
    belongs_to :user, User

    timestamps()
  end

  def san_balance(%{address: address}, _, _) do
    {:ok, Ethauth.san_balance(address)}
  end
end
