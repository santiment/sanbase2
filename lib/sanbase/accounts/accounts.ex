defmodule Sanbase.Accounts do
  import Ecto.Query, only: [from: 2]

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

  The weekly newsletter is a part of the marketing consent
  (`marketing_accepted`): giving the consent subscribes the user to the
  newsletter and withdrawing it unsubscribes, through
  `Sanbase.Email.ListSubscription`. The newsletter can also be changed on its
  own from the settings toggle, which does not touch the marketing consent.
  Both changes are recorded with their source (see `Sanbase.Email.ListConsent`).
  Writing the same value again changes nothing and does not touch Mailjet.

  The consent source is the signup dialog while the privacy policy is not yet
  accepted, and the /privacy-policy page afterwards.

  An unticked marketing checkbox in the signup dialog means no new consent, not a
  withdrawal, so it does not change anything.
  """
  @spec update_terms_and_conditions(User.t(), map()) :: {:ok, User.t()} | {:error, term()}
  def update_terms_and_conditions(%User{} = user, attrs) do
    source = if user.privacy_policy_accepted, do: :privacy_page, else: :signup_dialog

    {marketing_accepted, attrs} =
      case Map.pop(attrs, :marketing_accepted) do
        {false, attrs} when source == :signup_dialog -> {nil, attrs}
        result -> result
      end

    Repo.transaction(fn ->
      with {:ok, previous} <- lock_marketing_accepted(user.id),
           {:ok, user} <- user |> User.terms_changeset(attrs) |> Repo.update(),
           {:ok, newsletter_changed?} <-
             maybe_change_marketing(user.id, previous, marketing_accepted, source) do
        marketing_accepted =
          if is_boolean(marketing_accepted), do: marketing_accepted, else: previous

        {%{user | marketing_accepted: marketing_accepted}, newsletter_changed?}
      else
        {:error, error} -> Repo.rollback(error)
      end
    end)
    |> case do
      {:ok, {user, newsletter_changed?}} ->
        if newsletter_changed?,
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

  defp lock_marketing_accepted(user_id) do
    from(u in User, where: u.id == ^user_id, select: u.marketing_accepted, lock: "FOR UPDATE")
    |> Repo.one()
    |> case do
      nil -> {:error, :user_not_found}
      value -> {:ok, value}
    end
  end

  # Giving or withdrawing the marketing consent also subscribes to or
  # unsubscribes from the newsletter. Returns whether the newsletter changed.
  defp maybe_change_marketing(user_id, previous, value, source)
       when is_boolean(value) and value != previous do
    from(u in User, where: u.id == ^user_id)
    |> Repo.update_all(set: [marketing_accepted: value])

    with {:ok, _} <- Sanbase.Email.ListConsent.create(user_id, :marketing, value, source) do
      Sanbase.Email.ListSubscription.change(user_id, :newsletter, value, source)
    end
  end

  defp maybe_change_marketing(_user_id, _previous, _value, _source), do: {:ok, false}

  @doc """
  Apply a newsletter signup made from a website form (`emailLogin` with
  `subscribeToWeeklyNewsletter: true`) once the user has verified the email
  address. It subscribes only to the newsletter, not to the broader marketing
  consent. Failures are logged and do not fail the login.
  """
  @spec confirm_newsletter_opt_in(User.t()) :: {:ok, User.t()}
  def confirm_newsletter_opt_in(%User{newsletter_opt_in_pending: true} = user) do
    with {:ok, _changed?} <-
           Sanbase.Email.ListSubscription.set(user.id, :newsletter, true, :website_form),
         {:ok, user} <-
           user |> User.changeset(%{newsletter_opt_in_pending: false}) |> Repo.update() do
      {:ok, user}
    else
      {:error, error} ->
        Logger.error(
          "Failed to apply the newsletter opt-in for user #{user.id}: #{inspect(error)}"
        )

        {:ok, user}
    end
  end

  def confirm_newsletter_opt_in(%User{} = user), do: {:ok, user}

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

  def update_profile(%User{} = user, attrs) do
    User.update(user, Map.take(attrs, @profile_fields))
  end

  def reload_user_settings(%User{} = user) do
    Repo.preload(user, :user_settings, force: true)
  end
end
