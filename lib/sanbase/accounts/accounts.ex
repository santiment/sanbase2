defmodule Sanbase.Accounts do
  alias Sanbase.Repo
  alias Sanbase.Accounts.User
  alias Sanbase.Accounts.EthAccount
  alias Sanbase.Accounts.ProtectedUser

  @doc """
  True when this user has activity-traces hidden (NDA-protected). Used by
  the privacy-masking pipeline to short-circuit logging, ClickHouse system
  query persistence, Kafka api_call_data exports, and MCP tool-invocation
  analytics. The decision is cached in `Sanbase.Accounts.ProtectedUser`.
  """
  @spec activity_traces_hidden?(non_neg_integer() | nil) :: boolean()
  defdelegate activity_traces_hidden?(user_id), to: ProtectedUser

  @doc """
  Sentinel string used wherever a value would normally be persisted/logged
  for an `activity_traces_hidden?/1` user. Kept identical across surfaces
  so downstream consumers (Kafka, ClickHouse readers, MCP analytics) can
  recognize a masked row with a single equality check, and so an engineer
  who sees the literal in data can grep `activity_traces_hidden` and land
  on the masking pipeline immediately.
  """
  @spec masked_sentinel() :: String.t()
  def masked_sentinel(), do: "<activity_traces_hidden>"

  @terms_and_conditions_fields [:privacy_policy_accepted, :marketing_accepted]
  @profile_fields [:description, :website_url, :twitter_handle, :avatar_url]

  def get_user(user_id_or_ids) do
    User.by_id(user_id_or_ids)
  end

  def get_user!(user_id_or_ids) do
    case User.by_id(user_id_or_ids) do
      {:ok, user} -> user
      {:error, error} -> raise(error)
    end
  end

  @doc ~s"""
  Evolve the registration state by performing `action` and storing `data`.

  The registration state is a JSON map with `state` and `data` fields. Actions
  can be:
    - send_login_email
    - google_oauth
    - twitter_oauth
    - eth_login
    - email_login_verify
    - login

  Performing an action either moves the state to a different state or keep the same
  state. The state is kept when it is already `finished`, then any action is noop,
  as the registration has been finished.

  The `data` field keeps values like `origin_url`, `login_origin`, etc. that can be
  used in events emitting after the state reaches a given value after some transition.
  For example, `send_email_login` can put `origin_url`, but only after performing
  `email_login_verify` the `:register_user` event can be emitted, containing the
  URL stored before.
  """
  @spec forward_registration(User.t(), String.t(), Map.t()) ::
          {:ok, :evolve_state | :keep_state, User.t()} | no_return()
  def forward_registration(%User{} = user, action, data) do
    %{registration_state: %{"state" => current_state}} = user

    case User.RegistrationState.forward(user, action, data) do
      :keep_state ->
        {:ok, :keep_state, user}

      {:next_state, state, data} ->
        registration_state = %{"state" => state, "data" => data, "datetime" => DateTime.utc_now()}

        case User.atomic_update_registration_state(user.id, current_state, registration_state) do
          {1, [user]} -> {:ok, :evolve_state, user}
          {0, _} -> {:ok, :keep_state, user}
        end
    end
  end

  @doc ~s"""
  Create a new user with an ETH address. The address is created and linked in the
  ETH Accounts, but also set as the username.
  """
  @spec create_user_with_eth_address(String.t()) :: {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  def create_user_with_eth_address(address) when is_binary(address) do
    multi_result =
      Ecto.Multi.new()
      |> Ecto.Multi.run(:add_user, fn _, _ -> User.create(%{}) end)
      |> Ecto.Multi.run(:add_eth_account, fn _repo, %{add_user: %User{} = user} ->
        EthAccount.create(user.id, address)
      end)
      |> Repo.transaction()

    case multi_result do
      {:ok, %{add_user: user}} ->
        {:ok, user}

      {:error, _, reason, _} ->
        {:error, reason}
    end
  end

  @doc ~s"""
  Update the user's profile-visible fields (description, website_url, twitter_handle,
  avatar_url). Allowlist enforced regardless of caller-supplied keys.
  """
  @spec update_profile(User.t(), map()) :: {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  def update_profile(%User{} = user, attrs) do
    User.update(user, Map.take(attrs, @profile_fields))
  end

  @doc ~s"""
  Update the user's terms and conditions acceptance flags. Only
  `:privacy_policy_accepted` and `:marketing_accepted` are accepted. `nil` values
  are dropped so callers can pass partial updates.
  """
  @spec update_terms_and_conditions(User.t(), map()) ::
          {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  def update_terms_and_conditions(%User{} = user, attrs) do
    attrs =
      attrs
      |> Map.take(@terms_and_conditions_fields)
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Map.new()

    User.update(user, attrs)
  end

  @doc ~s"""
  Reload the user's `:user_settings` association, bypassing any prior preload.
  """
  @spec reload_user_settings(User.t()) :: User.t()
  def reload_user_settings(%User{} = user) do
    Repo.preload(user, :user_settings, force: true)
  end
end
