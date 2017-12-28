defmodule Sanbase.Auth.User do
  use Ecto.Schema
  import Ecto.Changeset

  alias Sanbase.Auth.{User, EthAccount}

  @salt_length 64

  schema "users" do
    field(:email, :string)
    field(:username, :string)
    field(:salt, :string)

    has_many(:eth_accounts, EthAccount)

    timestamps()
  end

  def generate_salt do
    :crypto.strong_rand_bytes(@salt_length) |> Base.url_encode64() |> binary_part(0, @salt_length)
  end

  def changeset(%User{} = user, attrs \\ %{}) do
    user
    |> cast(attrs, [:email, :username, :salt])
    |> unique_constraint(:email)
  end

  def san_balance(%User{eth_accounts: eth_accounts}) do
    eth_accounts
    |> EthAccount.san_balance()
    |> Enum.sum()
  end
end
