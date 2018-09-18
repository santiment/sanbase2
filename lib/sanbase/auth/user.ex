defmodule Sanbase.Auth.User do
  use Ecto.Schema
  use Timex.Ecto.Timestamps

  import Ecto.Changeset

  alias Sanbase.Auth.{
    User,
    EthAccount,
    UserApikeyToken
  }

  alias Sanbase.Voting.{Vote, Post}
  alias Sanbase.UserLists.UserList
  alias Sanbase.Repo

  @verification_email_template "login"

  # The Login links will be valid 1 hour
  @login_email_valid_minutes 60

  # The login link will be valid for 10
  @login_email_valid_after_validation_minutes 10

  @salt_length 64
  @email_token_length 64

  # 5 minutes
  @san_balance_cache_seconds 60 * 5

  # Fallback username and email for Insights owned by deleted user accounts
  @insights_fallback_username "anonymous"
  @insights_fallback_email "anonymous@santiment.net"

  require Mockery.Macro
  defp mandrill_api, do: Mockery.Macro.mockable(Sanbase.MandrillApi)

  schema "users" do
    field(:email, :string)
    field(:email_candidate, :string)
    field(:username, :string)
    field(:salt, :string)
    field(:san_balance, :decimal)
    field(:san_balance_updated_at, Timex.Ecto.DateTime)
    field(:email_token, :string)
    field(:email_token_generated_at, Timex.Ecto.DateTime)
    field(:email_token_validated_at, Timex.Ecto.DateTime)
    field(:consent_id, :string)
    field(:test_san_balance, :decimal)

    # GDPR related fields
    field(:privacy_policy_accepted, :boolean, default: false)
    field(:marketing_accepted, :boolean, default: false)

    has_many(:eth_accounts, EthAccount, on_delete: :delete_all)
    has_many(:votes, Vote, on_delete: :delete_all)
    has_many(:apikey_tokens, UserApikeyToken, on_delete: :delete_all)
    has_many(:user_lists, UserList, on_delete: :delete_all)
    has_many(:posts, Post, on_delete: :delete_all)

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
    |> cast(attrs, [
      :email,
      :email_candidate,
      :email_token_validated_at,
      :username,
      :salt,
      :test_san_balance,
      :privacy_policy_accepted,
      :marketing_accepted
    ])
    |> normalize_username(attrs)
    |> validate_change(:username, &validate_username_change/2)
    |> validate_change(:email_candidate, &validate_email_candidate_change/2)
    |> unique_constraint(:email)
    |> unique_constraint(:username)
  end

  def ascii_username?(nil), do: true

  def ascii_username?(username) do
    username
    |> String.to_charlist()
    |> List.ascii_printable?()
  end

  defp normalize_username(changeset, %{username: username}) when not is_nil(username) do
    put_change(changeset, :username, String.trim(username))
  end

  defp normalize_username(changeset, _), do: changeset

  defp validate_username_change(_, username) do
    if ascii_username?(username) do
      []
    else
      [username: "Username can contain only latin letters and numbers"]
    end
  end

  defp validate_email_candidate_change(_, email_candidate) do
    if Repo.get_by(User, email: email_candidate) do
      [email: "Email has already been taken"]
    else
      []
    end
  end

  def san_balance_cache_stale?(%User{san_balance_updated_at: nil}), do: true

  def san_balance_cache_stale?(%User{san_balance_updated_at: san_balance_updated_at}) do
    Timex.diff(Timex.now(), san_balance_updated_at, :seconds) > @san_balance_cache_seconds
  end

  def update_san_balance_changeset(user) do
    user = Repo.preload(user, :eth_accounts)
    san_balance = san_balance_for_eth_accounts(user.eth_accounts)

    user
    |> change(san_balance: san_balance, san_balance_updated_at: Timex.now())
  end

  def san_balance(%User{test_san_balance: test_san_balance} = _user)
      when not is_nil(test_san_balance) do
    {:ok, test_san_balance}
  end

  def san_balance(%User{san_balance: san_balance} = user) do
    if san_balance_cache_stale?(user) do
      update_san_balance_changeset(user)
      |> Repo.update()
      |> case do
        {:ok, user} ->
          {:ok, user |> Map.get(:san_balance)}

        {:error, error} ->
          {:error, error}
      end
    else
      {:ok, san_balance}
    end
  end

  def san_balance!(%User{} = user) do
    case san_balance(user) do
      {:ok, san_balance} -> san_balance
      {:error, error} -> raise(error)
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
        %User{}
        |> changeset(%{email_candidate: email, username: username, salt: generate_salt()})
        |> Repo.insert()

      user ->
        {:ok, user}
    end
  end

  def find_by_email_candidate(email_candidate, email_token) do
    case Repo.get_by(User, email_candidate: email_candidate, email_token: email_token) do
      nil ->
        {:error, "Can't find user"}

      user ->
        {:ok, user}
    end
  end

  def update_email_token(user, consent \\ nil) do
    user
    |> change(
      email_token: generate_email_token(),
      email_token_generated_at: Timex.now(),
      email_token_validated_at: nil,
      consent_id: consent
    )
    |> Repo.update()
  end

  def update_email(user) do
    user
    |> changeset(%{
      email_token_validated_at: user.email_token_validated_at || Timex.now(),
      email: user.email_candidate,
      email_candidate: nil
    })
    |> Repo.update()
  end

  def set_email_candidate(user, email_candidate) do
    user
    |> changeset(%{email_candidate: email_candidate})
    |> Repo.update()
  end

  def email_token_valid?(user, token) do
    cond do
      user.email_token != token ->
        false

      Timex.diff(Timex.now(), user.email_token_generated_at, :minutes) >
          @login_email_valid_minutes ->
        false

      user.email_token_validated_at == nil ->
        true

      Timex.diff(Timex.now(), user.email_token_validated_at, :minutes) >
          @login_email_valid_after_validation_minutes ->
        false

      true ->
        true
    end
  end

  def send_verification_email(user) do
    mandrill_api().send(@verification_email_template, user.email_candidate, %{
      LOGIN_LINK: SanbaseWeb.Endpoint.login_url(user.email_token, user.email_candidate)
    })
  end

  def by_id(user_id) when is_integer(user_id) do
    case Sanbase.Repo.get_by(User, id: user_id) do
      nil ->
        {:error, "Cannot fetch the user with id #{user_id}"}

      user ->
        {:ok, user}
    end
  end

  def insights_fallback_username, do: @insights_fallback_username
  def insights_fallback_email, do: @insights_fallback_email
end
