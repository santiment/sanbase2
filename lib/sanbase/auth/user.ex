defmodule Sanbase.Auth.User do
  use Ecto.Schema

  alias Sanbase.Auth.EthAccount

  schema "users" do
    field :email, :string
    field :username, :string
    field :salt, :string

    has_many :eth_accounts, EthAccount

    timestamps()
  end
end
