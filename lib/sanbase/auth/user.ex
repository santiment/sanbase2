defmodule Sanbase.Auth.User do
  use Ecto.Schema
  import Ecto.Changeset
  use Timex.Ecto.Timestamps

  alias Sanbase.Auth.{User, EthAccount}
  alias Sanbase.Repo

  @salt_length 64

  # 5 minutes
  @san_balance_cache_seconds 60 * 5

  schema "users" do
    field(:email, :string)
    field(:username, :string)
    field(:salt, :string)
    field(:san_balance, :decimal)
    field(:san_balance_updated_at, Timex.Ecto.DateTime)

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

  def san_balance_cache_stale?(%User{san_balance_updated_at: nil}), do: true

  def san_balance_cache_stale?(%User{san_balance_updated_at: san_balance_updated_at}) do
    Timex.diff(Timex.now(), san_balance_updated_at, :seconds) > @san_balance_cache_seconds
  end

  def update_san_balance_changeset(%User{eth_accounts: eth_accounts} = user) do
    san_balance = san_balance_for_eth_accounts(eth_accounts)

    user
    |> change(san_balance: san_balance, san_balance_updated_at: Timex.now())
  end

  def san_balance!(%User{san_balance: san_balance} = user) do
    if san_balance_cache_stale?(user) do
      update_san_balance_changeset(user)
      |> Repo.update!()
      |> Map.get(:san_balance)
    else
      san_balance
    end
  end

  defp san_balance_for_eth_accounts(eth_accounts) do
    eth_accounts
    |> Enum.map(&EthAccount.san_balance/1)
    |> Enum.sum()
  end
end
