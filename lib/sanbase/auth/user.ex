defmodule Sanbase.Auth.User do
  use Ecto.Schema

  alias Sanbase.Auth.EthAccount

  @salt_length 64

  schema "users" do
    field :email, :string
    field :username, :string
    field :salt, :string

    has_many :eth_accounts, EthAccount

    timestamps()
  end

  def generate_salt do
    :crypto.strong_rand_bytes(@salt_length) |> Base.url_encode64 |> binary_part(0, @salt_length)
  end
end
