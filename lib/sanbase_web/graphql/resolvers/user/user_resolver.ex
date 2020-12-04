defmodule SanbaseWeb.Graphql.Resolvers.UserResolver do
  require Logger

  alias SanbaseWeb.Graphql.Helpers.Utils
  alias Sanbase.Auth.{User, EthAccount}
  alias Sanbase.InternalServices.Ethauth
  alias Sanbase.Auth.{User, EthAccount, UserFollower}
  alias Sanbase.Repo
  alias Ecto.Multi
  alias Sanbase.Billing.Subscription.SignUpTrial

  def email(%User{email: nil}, _args, _resolution), do: {:ok, nil}

  def email(%User{id: id, email: email}, _args, %{
        context: %{auth: %{current_user: %User{id: id}}}
      }) do
    {:ok, email}
  end

  def email(%User{} = user, _args, _resolution) do
    {:ok, User.Public.hide_private_data(user).email}
  end

  def permissions(
        %User{} = user,
        _args,
        _resolution
      ) do
    {:ok, User.Permissions.permissions(user)}
  end

  @spec san_balance(%User{}, map(), Absinthe.Resolution.t()) :: {:ok, float()}
  def san_balance(
        %User{} = user,
        _args,
        _res
      ) do
    case User.san_balance(user) do
      {:ok, san_balance} ->
        {:ok, san_balance || 0}

      {:error, error} ->
        Logger.warn("Error getting a user's san balance. Reason: #{inspect(error)}")
        {:nocache, {:ok, 0.0}}
    end
  end

  def api_calls_history(%User{} = user, %{from: from, to: to, interval: interval}, _resolution) do
    Sanbase.Clickhouse.ApiCallData.api_call_history(user.id, from, to, interval)
  end

  def current_user(_root, _args, %{
        context: %{auth: %{current_user: user}}
      }) do
    {:ok, user}
  end

  def current_user(_root, _args, _context), do: {:ok, nil}

  def get_user(_root, %{selector: selector}, _resolution) when map_size(selector) != 1 do
    {:error, "Provide exactly one field in the user selector object"}
  end

  def get_user(_root, %{selector: selector}, _resolution) do
    case User.by_selector(selector) do
      nil -> {:error, "Cannot fetch user by: #{inspect(selector)}"}
      user -> {:ok, user}
    end
  end

  def following(%User{id: user_id}, _args, _resolution) do
    following = UserFollower.followed_by(user_id)

    {:ok, %{count: length(following), users: following}}
  end

  def followers(%User{id: user_id}, _args, _resolution) do
    followers = UserFollower.followers_of(user_id)

    {:ok, %{count: length(followers), users: followers}}
  end

  def eth_login(
        _root,
        %{signature: signature, address: address, message_hash: message_hash} = args,
        _resolution
      ) do
    with true <- Ethauth.verify_signature(signature, address, message_hash),
         {:ok, user} <- fetch_user(args, EthAccount.by_address(address)),
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

  def email_login(%{email: email} = args, %{
        context: %{origin_url: origin_url}
      }) do
    with {:ok, user} <- User.find_or_insert_by_email(email, %{username: args[:username]}),
         {:ok, user} <- User.update_email_token(user, args[:consent]),
         {:ok, _user} <- User.send_login_email(user, origin_url, args) do
      {:ok, %{success: true, first_login: user.first_login}}
    else
      _ -> {:error, message: "Can't login"}
    end
  end

  def email_login_verify(%{token: token, email: email}, _resolution) do
    with {:ok, user} <- User.find_or_insert_by_email(email),
         true <- User.email_token_valid?(user, token),
         _ <- create_free_trial_on_signup(user),
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
    User.change_username(user, new_username)
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

  def change_avatar(_root, %{avatar_url: avatar_url}, %{
        context: %{auth: %{auth_method: :user_token, current_user: user}}
      }) do
    User.update_avatar_url(user, avatar_url)
    |> case do
      {:ok, user} ->
        {:ok, user}

      {:error, changeset} ->
        {
          :error,
          message: "Cannot change the avatar", details: Utils.error_details(changeset)
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
    case User.remove_eth_account(user, address) do
      true ->
        {:ok, user}

      {:error, reason} ->
        error_msg =
          "Could not remove an ethereum address for user #{user.id}. Reason: #{inspect(reason)}"

        {:error, error_msg}
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

    user
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
    _ = EthAccount.create(%{user_id: user.id, address: address})

    {:ok, user}
  end

  # No eth account and no user logged in
  defp fetch_user(%{address: address}, nil) do
    Multi.new()
    |> Multi.insert(
      :add_user,
      User.changeset(%User{}, %{
        username: address,
        salt: User.generate_salt(),
        first_login: true,
        is_registered: true
      })
    )
    |> Multi.run(:add_eth_account, fn _repo, %{add_user: %User{id: id}} ->
      eth_account =
        EthAccount.changeset(%EthAccount{}, %{user_id: id, address: address})
        |> Repo.insert()

      {:ok, eth_account}
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{add_user: user}} ->
        SignUpTrial.create_subscription(user.id)
        {:ok, user}

      {:error, _, reason, _} ->
        {:error, message: reason}
    end
  end

  # Existing eth account, login as the user of the eth account
  defp fetch_user(_, %EthAccount{user_id: user_id}) do
    User.by_id(user_id)
  end

  # when `email_token_validated_at` is nil - user haven't completed registration
  defp create_free_trial_on_signup(%User{is_registered: false} = user) do
    SignUpTrial.create_subscription(user.id)
  end

  defp create_free_trial_on_signup(%User{is_registered: true}), do: :ok
end
