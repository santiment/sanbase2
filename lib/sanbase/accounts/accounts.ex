defmodule Sanbase.Accounts do
  alias Sanbase.Repo
  alias Sanbase.Accounts.User
  alias Sanbase.Accounts.EthAccount
  alias Sanbase.Accounts.ProtectedUser

  require Logger

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

  @doc """
  Update the privacy policy and marketing consent of a user.

  `marketing_accepted` is the consent to the weekly newsletter (see
  `Sanbase.Email.Lists`). It is changed through `Sanbase.Email.ListSubscription`,
  which keeps the newsletter settings in sync, records the consent and adds or
  removes the user in Mailjet. Writing the same value again does not touch
  Mailjet.

  The consent source is the signup dialog while the privacy policy is not yet
  accepted, and the /privacy-policy page afterwards.

  An unticked marketing checkbox in the signup dialog means no new consent, not a
  withdrawal, so it does not remove a consent the user already gave (e.g. through
  the newsletter form on santiment.net right before verifying the email).
  """
  @spec update_terms_and_conditions(User.t(), map()) :: {:ok, User.t()} | {:error, term()}
  def update_terms_and_conditions(%User{} = user, attrs) do
    source = if user.privacy_policy_accepted, do: :privacy_page, else: :signup_dialog

    {marketing_accepted, attrs} =
      case Map.pop(attrs, :marketing_accepted) do
        {false, attrs} when source == :signup_dialog -> {nil, attrs}
        result -> result
      end

    changeset = User.terms_changeset(user, attrs)

    Repo.transaction(fn ->
      with {:ok, user} <- Repo.update(changeset),
           {:ok, changed?} <- maybe_change_newsletter(user, marketing_accepted, source) do
        user =
          if is_boolean(marketing_accepted),
            do: %{user | marketing_accepted: marketing_accepted},
            else: user

        {user, changed?}
      else
        {:error, error} -> Repo.rollback(error)
      end
    end)
    |> case do
      {:ok, {user, changed?}} ->
        if changed?,
          do:
            Sanbase.Email.ListSubscription.notify_mailjet(
              user.id,
              :newsletter,
              marketing_accepted
            )

        {:ok, user}

      {:error, error} ->
        {:error, error}
    end
  end

  defp maybe_change_newsletter(user, value, source) when is_boolean(value) do
    Sanbase.Email.ListSubscription.change(user.id, :newsletter, value, source)
  end

  defp maybe_change_newsletter(_user, _value, _source), do: {:ok, false}

  @doc """
  Apply a newsletter signup made from a website form (`emailLogin` with
  `subscribeToWeeklyNewsletter: true`) once the user has verified the email
  address. Failures are logged and do not fail the login.
  """
  @spec confirm_newsletter_opt_in(User.t()) :: {:ok, User.t()}
  def confirm_newsletter_opt_in(%User{newsletter_opt_in_pending: true} = user) do
    with {:ok, _changed?} <-
           Sanbase.Email.ListSubscription.set(user.id, :newsletter, true, :website_form),
         {:ok, user} <-
           user |> User.changeset(%{newsletter_opt_in_pending: false}) |> Repo.update() do
      {:ok, %{user | marketing_accepted: true}}
    else
      {:error, error} ->
        Logger.error(
          "Failed to apply the newsletter opt-in for user #{user.id}: #{inspect(error)}"
        )

        {:ok, user}
    end
  end

  def confirm_newsletter_opt_in(%User{} = user), do: {:ok, user}

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
end
