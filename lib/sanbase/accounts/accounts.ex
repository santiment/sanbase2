defmodule Sanbase.Accounts do
  alias Sanbase.Repo
  alias __MODULE__.{User, EthAccount}

  import Ecto.Query
  import Sanbase.Accounts.User.Ecto, only: [registration_state_equals: 1]

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
  @spec forward_registration(User.t(), String.t(), map) ::
          {:ok, :evolve_state | :keep_state, User.t()} | no_return()
  def forward_registration(%User{} = user, action, data) do
    %{registration_state: %{"state" => current_state}} = user

    case User.RegistrationState.forward(user, action, data) do
      :keep_state ->
        {:ok, :keep_state, user}

      {:next_state, state, data} ->
        registration_state = %{"state" => state, "data" => data}

        case atomic_update(user.id, current_state, registration_state) do
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
      |> Ecto.Multi.run(:add_user, fn _, _ -> User.create(%{username: address}) end)
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

  defp atomic_update(user_id, old_state, new_registration_state) do
    # Atomic update. If the same code is execute from multiple processes or nodes
    # only one of them should succeed
    from(
      user in User,
      where: user.id == ^user_id and registration_state_equals(old_state),
      update: [set: [registration_state: ^new_registration_state]],
      select: user
    )
    |> Repo.update_all([])
  end
end
