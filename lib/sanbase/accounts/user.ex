defmodule Sanbase.Accounts.User do
  @moduledoc false
  use Ecto.Schema

  import __MODULE__.Validation
  import Ecto.Changeset
  import Ecto.Query
  import Sanbase.Accounts.EventEmitter, only: [emit_event: 3]

  alias Sanbase.Accounts.EthAccount
  alias Sanbase.Accounts.User
  alias Sanbase.Accounts.UserApikeyToken
  alias Sanbase.Accounts.UserFollower
  alias Sanbase.Accounts.UserRole
  alias Sanbase.Accounts.UserSettings
  alias Sanbase.Alert.HistoricalActivity
  alias Sanbase.Billing.Subscription
  alias Sanbase.Insight.Post
  alias Sanbase.Repo
  alias Sanbase.Telegram
  alias Sanbase.UserList
  alias Sanbase.Vote

  @salt_length 64

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

  @type t :: %__MODULE__{
          email: String.t(),
          username: String.t(),
          name: String.t(),
          first_login: boolean(),
          avatar_url: String.t(),
          registration_state: map(),
          is_superuser: boolean(),
          privacy_policy_accepted: boolean(),
          marketing_accepted: boolean(),
          user_settings: map(),
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  schema "users" do
    field(:email, :string)
    field(:username, :string)
    field(:name, :string)
    field(:stripe_customer_id, :string)
    field(:salt, :string)
    field(:email_candidate, :string)
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
    field(:first_login, :boolean, default: false, virtual: true)
    field(:avatar_url, :string)
    field(:is_registered, :boolean, default: false)
    field(:registration_state, :map)
    field(:is_superuser, :boolean, default: false)
    field(:twitter_id, :string)

    # GDPR related fields
    field(:privacy_policy_accepted, :boolean, default: false)
    field(:marketing_accepted, :boolean, default: false)
    has_one(:user_settings, UserSettings, on_delete: :delete_all)

    has_one(:telegram_user_tokens, Telegram.UserToken, on_delete: :delete_all)
    has_one(:uniswap_staking, User.UniswapStaking, on_delete: :delete_all)
    has_many(:timeline_events, Sanbase.Timeline.TimelineEvent, on_delete: :delete_all)
    has_many(:eth_accounts, EthAccount, on_delete: :delete_all)
    has_many(:votes, Vote, on_delete: :delete_all)
    has_many(:apikey_tokens, UserApikeyToken, on_delete: :delete_all)
    has_many(:user_lists, UserList, on_delete: :delete_all)
    has_many(:posts, Post, on_delete: :delete_all)
    has_many(:alerts_historical_activity, HistoricalActivity, on_delete: :delete_all)
    has_many(:followers, UserFollower, foreign_key: :user_id, on_delete: :delete_all)
    has_many(:following, UserFollower, foreign_key: :follower_id, on_delete: :delete_all)
    has_many(:subscriptions, Subscription, on_delete: :delete_all)
    has_many(:roles, {"user_roles", UserRole}, on_delete: :delete_all)
    has_many(:promo_trials, Subscription.PromoTrial, on_delete: :delete_all)
    has_many(:triggers, Sanbase.Alert.UserTrigger, on_delete: :delete_all)
    has_many(:chart_configurations, Sanbase.Chart.Configuration, on_delete: :delete_all)
    has_many(:user_events, Sanbase.Intercom.UserEvent, on_delete: :delete_all)
    has_many(:access_attempts, Sanbase.Accounts.AccessAttempt, on_delete: :delete_all)
    has_many(:short_urls, Sanbase.ShortUrl, on_delete: :delete_all)

    timestamps()
  end

  def get_name(%__MODULE__{} = user) do
    user.name || user.username || user.email || "Anon"
  end

  def get_unique_str(%__MODULE__{} = user) do
    user.email || user.username || user.twitter_id || "id_#{user.id}"
  end

  def get_signup_dt(%__MODULE__{registration_state: registration_state}) do
    case registration_state do
      %{"datetime" => datetime, "state" => "finished"} when is_binary(datetime) ->
        Sanbase.DateTimeUtils.from_iso8601!(datetime)

      _ ->
        nil
    end
  end

  def describe(%__MODULE__{} = user) do
    cond do
      user.username != nil -> "User with username #{user.username}"
      user.email != nil -> "User with email #{user.email}"
      user.twitter_id != nil -> "User with twitter_id #{user.twitter_id}"
      true -> "User with id #{user.id}"
    end
  end

  def generate_salt do
    @salt_length |> :crypto.strong_rand_bytes() |> Base.url_encode64() |> binary_part(0, @salt_length)
  end

  def changeset(%User{} = user, attrs \\ %{}) do
    attrs = Sanbase.DateTimeUtils.truncate_datetimes(attrs)

    user
    |> cast(attrs, [
      :avatar_url,
      :consent_id,
      :email_candidate_token_generated_at,
      :email_candidate_token_validated_at,
      :email_candidate_token,
      :email_candidate,
      :email_token_generated_at,
      :email_token_validated_at,
      :email_token,
      :email,
      :first_login,
      :is_registered,
      :is_superuser,
      :marketing_accepted,
      :privacy_policy_accepted,
      :salt,
      :stripe_customer_id,
      :test_san_balance,
      :twitter_id,
      :username,
      :name,
      :registration_state
    ])
    |> normalize_user_identificator(:username, attrs[:username])
    |> normalize_user_identificator(:email, attrs[:email])
    |> normalize_user_identificator(:email_candidate, attrs[:email_candidate])
    |> validate_change(:name, &validate_name_change/2)
    |> validate_change(:username, &validate_username_change/2)
    |> validate_change(:email_candidate, &validate_email_candidate_change/2)
    |> validate_change(:avatar_url, &validate_url_change/2)
    |> unique_constraint(:email)
    |> unique_constraint(:username)
    |> unique_constraint(:stripe_customer_id)
    |> unique_constraint(:twitter_id)
  end

  def san_balance(user), do: __MODULE__.SanBalance.san_balance(user)
  def san_balance_or_zero(user), do: __MODULE__.SanBalance.san_balance_or_zero(user)

  def create(attrs) do
    attrs = if attrs[:salt], do: attrs, else: Map.put(attrs, :salt, generate_salt())

    attrs =
      attrs
      |> Map.put(:first_login, true)
      |> Map.put_new(:registration_state, %{"state" => "init", "datetime" => DateTime.utc_now()})

    %__MODULE__{}
    |> changeset(attrs)
    |> Repo.insert()
    |> emit_event(:create_user, %{})
  end

  def by_id!(user_id) do
    case by_id(user_id) do
      {:ok, data} -> data
      {:error, error} -> raise(error)
    end
  end

  def by_id(user_id, opts \\ [])

  def by_id(user_id, opts) when is_integer(user_id) do
    query = from(u in __MODULE__, where: u.id == ^user_id)

    query =
      if Keyword.get(opts, :lock_for_update, false) do
        lock(query, "FOR UPDATE")
      else
        query
      end

    case Sanbase.Repo.one(query) do
      nil -> {:error, "Cannot fetch the user with id #{user_id}"}
      %__MODULE__{} = user -> {:ok, user}
    end
  end

  def by_id(user_ids, _opts) when is_list(user_ids) do
    users =
      Repo.all(
        from(u in __MODULE__,
          where: u.id in ^user_ids,
          order_by: fragment("array_position(?, ?::int)", ^user_ids, u.id),
          preload: [:eth_accounts, :user_settings]
        )
      )

    {:ok, users}
  end

  def by_search_text(search_text) do
    search_text = "%" <> search_text <> "%"

    Repo.all(
      from(u in __MODULE__,
        where: like(u.email, ^search_text),
        or_where: like(u.username, ^search_text),
        or_where: like(u.name, ^search_text)
      )
    )
  end

  @doc false
  def all_users do
    # Apparantly, it does not fetch all users.
    Repo.all(from(u in __MODULE__, order_by: [desc: u.updated_at], limit: 2000))
  end

  def by_email(email) when is_binary(email) do
    case Sanbase.Repo.get_by(User, email: email) do
      nil -> {:error, "Cannot fetch user with email #{email}"}
      %__MODULE__{} = user -> {:ok, user}
    end
  end

  def by_username(username) when is_binary(username) do
    case Sanbase.Repo.get_by(User, username: username) do
      nil -> {:error, "Cannot fetch user with username #{username}"}
      %__MODULE__{} = user -> {:ok, user}
    end
  end

  def by_twitter_id(twitter_id) when is_binary(twitter_id) do
    case Sanbase.Repo.get_by(User, twitter_id: twitter_id) do
      nil -> {:error, "Cannot fetch user with twitter_id #{twitter_id}"}
      %__MODULE__{} = user -> {:ok, user}
    end
  end

  def by_stripe_customer_id(stripe_customer_id) do
    case Repo.get_by(User, stripe_customer_id: stripe_customer_id) do
      nil -> {:error, "Cannot fetch user with stripe_customer_id #{stripe_customer_id}"}
      %__MODULE__{} = user -> {:ok, user}
    end
  end

  def by_selector(%{id: id}), do: by_id(Sanbase.Math.to_integer(id))
  def by_selector(%{email: email}), do: by_email(email)
  def by_selector(%{username: username}), do: by_username(username)
  def by_selector(%{twitter_id: twitter_id}), do: by_twitter_id(twitter_id)

  def update_field(%__MODULE__{} = user, field, value) do
    if Map.fetch!(user, field) == value do
      {:ok, user}
    else
      user |> changeset(%{field => value}) |> Repo.update()
    end
  end

  def find_or_insert_by(field, value, attrs \\ %{}) when field in [:email, :username, :twitter_id] do
    # When this function is used to create a new user during login/singup process
    # it **must** be followed by calling `Sanbase.Accounts.forward_registration/2`
    # so the registration progress can evolve in the proper direction
    value = normalize_user_identificator(field, value)

    case Repo.get_by(User, [{field, value}]) do
      nil ->
        user_create_attrs =
          Map.merge(
            attrs,
            %{field => value, salt: User.generate_salt(), first_login: true}
          )

        create(user_create_attrs)

      user ->
        {:ok, user}
    end
  end

  def change_name(%__MODULE__{name: name} = user, name), do: {:ok, user}

  def change_name(%__MODULE__{} = user, name) do
    user
    |> changeset(%{name: name})
    |> Repo.update()
    |> emit_event(:update_name, %{old_name: user.name, new_name: name})
  end

  def change_username(%__MODULE__{username: username} = user, username), do: {:ok, user}

  def change_username(%__MODULE__{} = user, username) do
    user
    |> changeset(%{username: username})
    |> Repo.update()
    |> emit_event(:update_username, %{old_username: user.username, new_username: username})
  end

  def anonymous_user_username, do: @anonymous_user_username
  def anonymous_user_email, do: @anonymous_user_email

  def anonymous_user_id do
    __MODULE__
    |> Repo.get_by(email: @anonymous_user_email, username: @anonymous_user_username)
    |> Map.get(:id)
  end

  def sanbase_bot_email, do: @sanbase_bot_email
  def sanbase_bot_email(idx), do: String.replace(@sanbase_bot_email, "@", "#{idx}@")

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

  @doc """
  Sync users' emails in Stripe.
  User might change his email in Sanbase, so we want keep Sanbase in sync with Stripe.
  """
  def sync_subscribed_users_with_changed_email do
    from(u in __MODULE__,
      where:
        not is_nil(u.email) and
          not is_nil(u.email_candidate_token_validated_at) and
          not is_nil(u.stripe_customer_id),
      select: %{email: u.email, stripe_customer_id: u.stripe_customer_id}
    )
    |> Repo.all()
    |> Enum.each(fn %{email: email, stripe_customer_id: stripe_customer_id} ->
      Sanbase.StripeApi.update_customer(stripe_customer_id, %{email: email})
    end)
  end

  def fetch_all_users_with_eth_account do
    Repo.all(from(u in __MODULE__, inner_join: ea in assoc(u, :eth_accounts), preload: :eth_accounts, distinct: true))
  end
end
