defmodule SanbaseWeb.Graphql.Resolvers.AccountResolver do
  require Logger

  alias SanbaseWeb.Graphql.Helpers.Utils
  alias Sanbase.Auth.{User, EthAccount}
  alias Sanbase.InternalServices.Ethauth
  alias Sanbase.Auth.{User, EthAccount}
  alias Sanbase.Repo
  alias Ecto.Multi

  def permissions(
        %User{} = user,
        _args,
        _resolution
      ) do
    User.permissions(user)
  end

  @spec san_balance(Sanbase.Auth.User.t(), map(), Absinthe.Resolution.t()) :: {:ok, float()}
  def san_balance(
        %User{} = user,
        _args,
        _res
      ) do
    with {:ok, san_balance} <- User.san_balance(user) do
      san_balance = san_balance || Decimal.new(0)
      {:ok, Decimal.to_float(san_balance)}
    else
      error ->
        Logger.warn("Error getting a user's san balance. Reason: #{inspect(error)}")
        {:ok, 0.0}
    end
  end

  def current_user(_root, _args, %{
        context: %{auth: %{current_user: user}}
      }) do
    {:ok, user}
  end

  def current_user(_root, _args, _context), do: {:ok, nil}

  def eth_login(
        %{signature: signature, address: address, message_hash: message_hash} = args,
        _resolution
      ) do
    with true <- Ethauth.verify_signature(signature, address, message_hash),
         {:ok, user} <- fetch_user(args, Repo.get_by(EthAccount, address: address)),
         {:ok, token, _claims} <- SanbaseWeb.Guardian.encode_and_sign(user, %{salt: user.salt}) do
      {:ok, %{user: user, token: token}}
    else
      {:error, reason} ->
        Logger.warn("Login failed: #{reason}")

        {:error, message: "Login failed"}

      _ ->
        Logger.warn("Login failed: invalid signature")
        {:error, message: "Login failed"}
    end
  end

  def email_login(%{email: email} = args, _resolution) do
    with {:ok, user} <- User.find_or_insert_by_email(email, args[:username]),
         {:ok, user} <- User.update_email_token(user, args[:consent]),
         {:ok, _user} <- User.send_login_email(user) do
      {:ok, %{success: true}}
    else
      _ -> {:error, message: "Can't login"}
    end
  end

  def email_login_verify(%{token: token, email: email}, _resolution) do
    with {:ok, user} <- User.find_or_insert_by_email(email),
         true <- User.email_token_valid?(user, token),
         {:ok, token, _claims} <- SanbaseWeb.Guardian.encode_and_sign(user, %{salt: user.salt}),
         {:ok, user} <- User.mark_email_token_as_validated(user) do
      {:ok, %{user: user, token: token}}
    else
      _ -> {:error, message: "Login failed"}
    end
  end

  def change_email(_root, %{email: email_candidate}, %{
        context: %{auth: %{auth_method: :user_token, current_user: user}}
      }) do
    with {:ok, user} <- User.update_email_candidate(user, email_candidate),
         {:ok, _user} <- User.send_verify_email(user) do
      {:ok, %{success: true}}
    else
      {:error, changeset} ->
        message = "Can't change current user's email to #{email_candidate}"
        Logger.warn(message)
        {:error, message: message, details: Utils.error_details(changeset)}
    end
  end

  def email_change_verify(
        %{token: email_candidate_token, email_candidate: email_candidate},
        _resolution
      ) do
    with {:ok, user} <- User.find_by_email_candidate(email_candidate, email_candidate_token),
         true <- User.email_candidate_token_valid?(user, email_candidate_token),
         {:ok, token, _claims} <- SanbaseWeb.Guardian.encode_and_sign(user, %{salt: user.salt}),
         {:ok, user} <- User.update_email_from_email_candidate(user) do
      {:ok, %{user: user, token: token}}
    else
      _ -> {:error, message: "Login failed"}
    end
  end

  def change_username(_root, %{username: new_username}, %{
        context: %{auth: %{auth_method: :user_token, current_user: user}}
      }) do
    Repo.get!(User, user.id)
    |> User.changeset(%{username: new_username})
    |> Repo.update()
    |> case do
      {:ok, user} ->
        {:ok, user}

      {:error, changeset} ->
        {
          :error,
          message: "Cannot update current user's username to #{new_username}",
          details: Utils.error_details(changeset)
        }
    end
  end

  def add_user_eth_address(
        _root,
        %{signature: signature, address: address, message_hash: message_hash},
        %{context: %{auth: %{auth_method: :user_token, current_user: user}}}
      ) do
    with true <- Ethauth.verify_signature(signature, address, message_hash),
         {:ok, _} <- User.add_eth_account(user, address) do
      {:ok, user}
    else
      {:error, reason} ->
        Logger.warn(
          "Could not add an ethereum address for user #{user.id}. Reason: #{inspect(reason)}"
        )

        {:error, "Could not add an ethereum address."}
    end
  end

  def remove_user_eth_address(_root, %{address: address}, %{
        context: %{auth: %{auth_method: :user_token, current_user: user}}
      }) do
    with true <- User.remove_eth_account(user, address) do
      {:ok, user}
    else
      {:error, reason} ->
        Logger.warn(
          "Could not remove an ethereum address for user #{user.id}. Reason: #{inspect(reason)}"
        )

        {:error, "Could not remove an ethereum address."}
    end
  end

  def update_terms_and_conditions(_root, args, %{
        context: %{auth: %{auth_method: :user_token, current_user: user}}
      }) do
    # Update only the provided arguments
    args =
      args
      |> Enum.reject(fn {_key, value} -> value == nil end)
      |> Enum.into(%{})

    Repo.get!(User, user.id)
    |> User.changeset(args)
    |> Repo.update()
    |> case do
      {:ok, user} ->
        {:ok, user}

      {:error, changeset} ->
        {
          :error,
          message: "Cannot update current user's terms and conditions",
          details: Utils.error_details(changeset)
        }
    end
  end

  # Private functions

  # No eth account and there is a user logged in
  defp fetch_user(
         %{address: address, context: %{auth: %{auth_method: :user_token, current_user: user}}},
         nil
       ) do
    %EthAccount{user_id: user.id, address: address}
    |> Repo.insert!()

    {:ok, user}
  end

  # No eth account and no user logged in
  defp fetch_user(%{address: address}, nil) do
    Multi.new()
    |> Multi.insert(
      :add_user,
      User.changeset(%User{}, %{username: address, salt: User.generate_salt()})
    )
    |> Multi.run(:add_eth_account, fn %{add_user: %User{id: id}} ->
      eth_account =
        EthAccount.changeset(%EthAccount{}, %{user_id: id, address: address})
        |> Repo.insert()

      {:ok, eth_account}
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{add_user: user}} -> {:ok, user}
      {:error, _, reason, _} -> {:error, message: reason}
    end
  end

  # Existing eth account, login as the user of the eth account
  defp fetch_user(_, %EthAccount{user_id: user_id}) do
    {:ok, Repo.get!(User, user_id)}
  end
end
