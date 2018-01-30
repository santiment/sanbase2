defmodule Sanbase.Auth.User do
  use Ecto.Schema
  import Ecto.Changeset
  use Timex.Ecto.Timestamps

  alias Sanbase.Auth.{User, EthAccount}
  alias Sanbase.Voting.Vote
  alias Sanbase.Repo
  alias Sanbase.MandrillApi

  @login_email_template "login"

  # The Login links will be valid 1 day
  @login_email_valid_minutes 24 * 60

  @salt_length 64
  @email_token_length 64

  # 5 minutes
  @san_balance_cache_seconds 60 * 5

  schema "users" do
    field(:email, :string)
    field(:username, :string)
    field(:salt, :string)
    field(:san_balance, :decimal)
    field(:san_balance_updated_at, Timex.Ecto.DateTime)
    field(:email_token, :string)
    field(:email_token_generated_at, Timex.Ecto.DateTime)

    has_many(:eth_accounts, EthAccount)
    has_many(:votes, Vote, on_delete: :delete_all)

    timestamps()
  end

  def generate_salt do
    :crypto.strong_rand_bytes(@salt_length) |> Base.url_encode64() |> binary_part(0, @salt_length)
  end

  def generate_email_token do
    :crypto.strong_rand_bytes(@email_token_length) |> Base.url_encode64()
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
    |> Enum.reduce(Decimal.new(0), &Decimal.add/2)
  end

  def find_or_insert_by_email(email, username \\ nil) do
    case Repo.get_by(User, email: email) do
      nil ->
        %User{email: email, username: username, salt: generate_salt()}
        |> Repo.insert()

      user ->
        {:ok, user}
    end
  end

  def update_email_token(user) do
    user
    |> change(email_token: generate_email_token(), email_token_generated_at: Timex.now())
    |> Repo.update()
  end

  def email_token_valid?(user, token) do
    user.email_token == token and
      Timex.diff(Timex.now(), user.email_token_generated_at, :minutes) <=
        @login_email_valid_minutes
  end

  def send_login_email(user) do
    MandrillApi.send(@login_email_template, user.email, %{
      login_link: SanbaseWeb.Endpoint.login_url(user.email_token, user.email)
    })
  end
end
