defmodule Sanbase.Auth.EthAccount do
  use Ecto.Schema

  alias Sanbase.Auth.User

  schema "eth_accounts" do
    field :address, :string
    belongs_to :user, User

    timestamps()
  end
end
