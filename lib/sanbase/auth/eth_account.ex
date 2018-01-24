defmodule Sanbase.Auth.EthAccount do
  use Ecto.Schema

  alias Sanbase.Auth.{User, EthAccount}

  @ethauth Mockery.of("Sanbase.InternalServices.Ethauth")

  schema "eth_accounts" do
    field :address, :string
    belongs_to :user, User

    timestamps()
  end

  def san_balance(%EthAccount{address: address}) do
    @ethauth.san_balance(address)
  end
end
