defmodule Sanbase.Auth.User do
  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query

  alias Sanbase.Auth.{
    User,
    EthAccount,
    UserApikeyToken,
    UserSettings
  }

  alias Sanbase.Vote
  alias Sanbase.Insight.Post
  alias Sanbase.UserList
  alias Sanbase.Repo
  alias Sanbase.Telegram
  alias Sanbase.Signal.HistoricalActivity
  alias Sanbase.Auth.UserFollower
  alias Sanbase.Billing.Subscription

  # The Login links will be valid 1 hour
  @login_email_valid_minutes 60

  # The login link will be valid for 10
  @login_email_valid_after_validation_minutes 10

  @salt_length 64
  @email_token_length 64

  # 5 minutes
  @san_balance_cache_seconds 60 * 5

  # Fallback username and email for Insights owned by deleted user accounts
  @anonymous_user_username "anonymous"
  @anonymous_user_email "anonymous@santiment.net"

  # User with free subscription that is used for external integration testing
  @sanbase_bot_email "sanbase.bot@santiment.net"

  @derive {Inspect,
           except: [
             :salt,
             :email_token,
             :email_token_generated_at,
             :email_token_validated_at,
             :email_candidate_token,
             :email_candidate_token_generated_at,
             :email_candidate_token_validated_at,
             :consent_id
           ]}

  require Mockery.Macro
  defp mandrill_api, do: Mockery.Macro.mockable(Sanbase.MandrillApi)

  schema "users" do
    field(:email, :string)
    field(:email_candidate, :string)
    field(:username, :string)
    field(:salt, :string)
    field(:san_balance, :decimal)
    field(:san_balance_updated_at, :naive_datetime)
    field(:email_token, :string)
    field(:email_token_generated_at, :naive_datetime)
    field(:email_token_validated_at, :naive_datetime)
    field(:email_candidate_token, :string)
    field(:email_candidate_token_generated_at, :naive_datetime)
    field(:email_candidate_token_validated_at, :naive_datetime)
    field(:consent_id, :string)
    field(:test_san_balance, :decimal)
    field(:stripe_customer_id, :string)
    field(:first_login, :boolean, default: false, virtual: true)
    field(:avatar_url, :string)
    field(:is_registered, :boolean, default: false)

    # GDPR related fields
    field(:privacy_policy_accepted, :boolean, default: false)
    field(:marketing_accepted, :boolean, default: false)

    has_one(:telegram_user_tokens, Telegram.UserToken, on_delete: :delete_all)
    has_one(:sign_up_trial, Sanbase.Billing.Subscription.SignUpTrial, on_delete: :delete_all)
    has_many(:eth_accounts, EthAccount, on_delete: :delete_all)
    has_many(:votes, Vote, on_delete: :delete_all)
    has_many(:apikey_tokens, UserApikeyToken, on_delete: :delete_all)
    has_many(:user_lists, UserList, on_delete: :delete_all)
    has_many(:posts, Post, on_delete: :delete_all)
    has_many(:signals_historical_activity, HistoricalActivity, on_delete: :delete_all)
    has_many(:followers, UserFollower, foreign_key: :user_id, on_delete: :delete_all)
    has_many(:following, UserFollower, foreign_key: :follower_id, on_delete: :delete_all)
    has_many(:subscriptions, Subscription, on_delete: :delete_all)
    has_many(:roles, {"user_roles", Sanbase.Auth.UserRole}, on_delete: :delete_all)
    has_many(:promo_trials, Sanbase.Billing.Subscription.PromoTrial, on_delete: :delete_all)
    has_many(:triggers, Sanbase.Signal.UserTrigger, on_delete: :delete_all)
    has_many(:chart_configurations, Sanbase.Chart.Configuration, on_delete: :delete_all)

    has_one(:user_settings, UserSettings, on_delete: :delete_all)

    timestamps()
  end

  def generate_salt() do
    :crypto.strong_rand_bytes(@salt_length) |> Base.url_encode64() |> binary_part(0, @salt_length)
  end

  def generate_email_token() do
    :crypto.strong_rand_bytes(@email_token_length) |> Base.url_encode64()
  end

  def changeset(%User{} = user, attrs \\ %{}) do
    attrs = Sanbase.DateTimeUtils.truncate_datetimes(attrs)

    user
    |> cast(attrs, [
      :email,
      :email_candidate,
      :email_candidate_token,
      :email_candidate_token_generated_at,
      :email_candidate_token_validated_at,
      :username,
      :salt,
      :test_san_balance,
      :privacy_policy_accepted,
      :marketing_accepted,
      :stripe_customer_id,
      :first_login,
      :avatar_url,
      :is_registered
    ])
    |> normalize_username(attrs)
    |> normalize_email(attrs[:email], :email)
    |> normalize_email(attrs[:email_candidate], :email_candidate)
    |> validate_change(:username, &validate_username_change/2)
    |> validate_change(:email_candidate, &validate_email_candidate_change/2)
    |> validate_change(:avatar_url, &validate_url_change/2)
    |> unique_constraint(:email)
    |> unique_constraint(:username)
    |> unique_constraint(:stripe_customer_id)
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

  defp normalize_email(changeset, nil, _), do: changeset

  defp normalize_email(changeset, email, field) do
    email =
      email
      |> String.downcase()
      |> String.trim()

    put_change(changeset, field, email)
  end

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

  defp validate_url_change(_, url) do
    case Sanbase.Validation.valid_url?(url) do
      :ok -> []
      {:error, msg} -> [avatar_url: msg]
    end
  end

  def san_balance_cache_stale?(%User{san_balance_updated_at: nil}), do: true

  def san_balance_cache_stale?(%User{san_balance_updated_at: san_balance_updated_at}) do
    naive_now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
    Timex.diff(naive_now, san_balance_updated_at, :seconds) > @san_balance_cache_seconds
  end

  def update_san_balance_changeset(user) do
    user = Repo.preload(user, :eth_accounts)
    san_balance = san_balance_for_eth_accounts(user)
    naive_now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    user
    |> change(
      san_balance_updated_at: naive_now,
      san_balance: san_balance
    )
  end

  @spec san_balance(%User{}) :: {:ok, float()} | {:ok, nil} | {:error, String.t()}
  def san_balance(%User{test_san_balance: test_san_balance})
      when not is_nil(test_san_balance) do
    {:ok, test_san_balance |> Sanbase.Math.to_float()}
  end

  def san_balance(%User{san_balance: san_balance} = user) do
    if san_balance_cache_stale?(user) do
      update_san_balance_changeset(user)
      |> Repo.update()
      |> case do
        {:ok, %{san_balance: san_balance}} ->
          {:ok, san_balance |> Sanbase.Math.to_float()}

        {:error, error} ->
          {:error, error}
      end
    else
      {:ok, san_balance |> Sanbase.Math.to_float()}
    end
  end

  @spec san_balance!(%User{}) :: float | nil | no_return
  def san_balance!(%User{} = user) do
    case san_balance(user) do
      {:ok, san_balance} -> san_balance
      {:error, error} -> raise(error)
    end
  end

  defp san_balance_for_eth_accounts(%User{eth_accounts: eth_accounts, san_balance: san_balance}) do
    eth_accounts_balances =
      eth_accounts
      |> Enum.map(&EthAccount.san_balance/1)
      |> Enum.reject(&is_nil/1)

    case Enum.member?(eth_accounts_balances, :error) do
      true -> san_balance
      _ -> Enum.reduce(eth_accounts_balances, 0, &Kernel.+/2)
    end
  end

  def find_or_insert_by_email(email, username \\ nil) do
    email = String.downcase(email)

    case Repo.get_by(User, email: email) do
      nil ->
        %User{email: email, username: username, salt: generate_salt(), first_login: true}
        |> Repo.insert()

      user ->
        {:ok, user}
    end
  end

  def find_by_email_candidate(email_candidate, email_candidate_token) do
    email_candidate = String.downcase(email_candidate)

    case Repo.get_by(User,
           email_candidate: email_candidate,
           email_candidate_token: email_candidate_token
         ) do
      nil ->
        {:error, "Can't find user with email candidate #{email_candidate}"}

      user ->
        {:ok, user}
    end
  end

  def update_email_token(user, consent \\ nil) do
    user
    |> change(
      email_token: generate_email_token(),
      email_token_generated_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second),
      email_token_validated_at: nil,
      consent_id: consent
    )
    |> Repo.update()
  end

  def update_email_candidate(user, email_candidate) do
    user
    |> changeset(%{
      email_candidate: email_candidate,
      email_candidate_token: generate_email_token(),
      email_candidate_token_generated_at:
        NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second),
      email_candidate_token_validated_at: nil
    })
    |> Repo.update()
  end

  def mark_email_token_as_validated(user) do
    validated_at =
      (user.email_token_validated_at || Timex.now())
      |> Timex.to_naive_datetime()
      |> NaiveDateTime.truncate(:second)

    user
    |> change(
      email_token_validated_at: validated_at,
      is_registered: true
    )
    |> Repo.update()
  end

  def update_email_from_email_candidate(user) do
    validated_at =
      (user.email_candidate_token_validated_at || Timex.now())
      |> Timex.to_naive_datetime()
      |> NaiveDateTime.truncate(:second)

    user
    |> changeset(%{
      email: user.email_candidate,
      email_candidate: nil,
      email_candidate_token_validated_at: validated_at
    })
    |> Repo.update()
  end

  def email_token_valid?(user, token) do
    naive_now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    cond do
      user.email_token != token ->
        false

      Timex.diff(naive_now, user.email_token_generated_at, :minutes) >
          @login_email_valid_minutes ->
        false

      user.email_token_validated_at == nil ->
        true

      Timex.diff(naive_now, user.email_token_validated_at, :minutes) >
          @login_email_valid_after_validation_minutes ->
        false

      true ->
        true
    end
  end

  def email_candidate_token_valid?(user, email_candidate_token) do
    naive_now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    cond do
      user.email_candidate_token != email_candidate_token ->
        false

      Timex.diff(naive_now, user.email_candidate_token_generated_at, :minutes) >
          @login_email_valid_minutes ->
        false

      user.email_candidate_token_validated_at == nil ->
        true

      Timex.diff(naive_now, user.email_candidate_token_validated_at, :minutes) >
          @login_email_valid_after_validation_minutes ->
        false

      true ->
        true
    end
  end

  def change_username(%__MODULE__{} = user, username) do
    user
    |> changeset(%{username: username})
    |> Repo.update()
  end

  def send_login_email(user, origin_url, args \\ %{}) do
    origin_url
    |> Sanbase.Email.Template.choose_login_template(first_login?: user.first_login)
    |> mandrill_api().send(user.email, %{
      LOGIN_LINK: SanbaseWeb.Endpoint.login_url(user.email_token, user.email, origin_url, args)
    })
  end

  def send_verify_email(user) do
    mandrill_api().send(
      Sanbase.Email.Template.verification_email_template(),
      user.email_candidate,
      %{
        VERIFY_LINK:
          SanbaseWeb.Endpoint.verify_url(user.email_candidate_token, user.email_candidate)
      }
    )
  end

  def all() do
    from(u in User, order_by: u.id)
    |> Sanbase.Repo.all()
  end

  def by_id(user_id) when is_integer(user_id) do
    case Sanbase.Repo.get_by(User, id: user_id) do
      nil ->
        {:error, "Cannot fetch the user with id #{user_id}"}

      user ->
        {:ok, user}
    end
  end

  def by_email(email) when is_binary(email) do
    Sanbase.Repo.get_by(User, email: email)
  end

  def by_selector(%{id: id}), do: Repo.get_by(__MODULE__, id: id)
  def by_selector(%{email: email}), do: Repo.get_by(__MODULE__, email: email)
  def by_selector(%{username: username}), do: Repo.get_by(__MODULE__, username: username)

  def users_with_monitored_watchlist_and_email() do
    from(u in User,
      join: ul in UserList,
      on: ul.user_id == u.id,
      where: not is_nil(u.email) and ul.is_monitored == true,
      distinct: true
    )
    |> Repo.all()
  end

  @spec add_eth_account(%User{}, String.t()) :: {:ok, %User{}} | {:error, Ecto.Changeset.t()}
  def add_eth_account(%User{id: user_id}, address) do
    EthAccount.changeset(%EthAccount{}, %{user_id: user_id, address: address})
    |> Repo.insert()
  end

  @doc ~s"""
  An EthAccount can be removed only if there is another mean to login - an email address
  or another ethereum address set. If the address that is being removed is the only
  address and there is no email, the user account will be lost as there won't be
  any way to log in
  """
  @spec remove_eth_account(%User{}, String.t()) :: true | {:error, String.t()}
  def remove_eth_account(%User{id: user_id} = user, address) do
    if can_remove_eth_account?(user, address) do
      from(
        ea in EthAccount,
        where: ea.user_id == ^user_id and ea.address == ^address
      )
      |> Repo.delete_all()
      |> case do
        {1, _} -> true
        {0, _} -> {:error, "Address #{address} does not exist or is not owned by user #{user_id}"}
      end
    else
      {:error,
       "Cannot remove ethereum address #{address}. There must be an email or other ethereum address set."}
    end
  end

  # Resource coud be watchlist, insight, user_trigger struct or any other struct which belongs to User
  def resource_user_count_map(resource) do
    from(
      r in resource,
      group_by: r.user_id,
      select: {r.user_id, count(r.user_id)}
    )
    |> Repo.all()
    |> Enum.into(%{})
  end

  def anonymous_user_username, do: @anonymous_user_username
  def anonymous_user_email, do: @anonymous_user_email

  def anonymous_user_id() do
    Repo.get_by(__MODULE__, email: @anonymous_user_email, username: @anonymous_user_username)
    |> Map.get(:id)
  end

  def sanbase_bot_email, do: @sanbase_bot_email

  def sanbase_bot_email(idx) do
    String.replace(@sanbase_bot_email, "@", "#{idx}@")
  end

  def has_credit_card_in_stripe?(user_id) do
    with {:ok, user} <- by_id(user_id),
         {:ok, customer} <- Sanbase.StripeApi.retrieve_customer(user) do
      customer.default_source != nil
    else
      _ -> false
    end
  end

  def update_avatar_url(%User{} = user, avatar_url) do
    user
    |> changeset(%{avatar_url: avatar_url})
    |> Repo.update()
  end

  defp can_remove_eth_account?(%User{id: user_id, email: email}, address) do
    count_other_accounts =
      from(ea in EthAccount,
        where: ea.user_id == ^user_id and ea.address != ^address
      )
      |> Repo.aggregate(:count, :id)

    count_other_accounts > 0 or not is_nil(email)
  end
end
