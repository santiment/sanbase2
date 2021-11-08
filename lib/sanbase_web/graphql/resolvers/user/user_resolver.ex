defmodule SanbaseWeb.Graphql.Resolvers.UserResolver do
  require Logger

  import Sanbase.Utils.ErrorHandling, only: [changeset_errors: 1]
  import Absinthe.Resolution.Helpers, except: [async: 1]

  alias Sanbase.InternalServices.Ethauth
  alias Sanbase.Accounts.{User, UserFollower}
  alias SanbaseWeb.Graphql.SanbaseDataloader

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

  def api_calls_history(
        %User{} = user,
        %{from: from, to: to, interval: interval} = args,
        _resolution
      ) do
    auth_method = Map.get(args, :auth_method, :all)
    Sanbase.Clickhouse.ApiCallData.api_call_history(user.id, from, to, interval, auth_method)
  end

  def api_calls_count(
        %User{} = user,
        %{from: from, to: to} = args,
        _resolution
      ) do
    auth_method = Map.get(args, :auth_method, :all)
    Sanbase.Clickhouse.ApiCallData.api_call_count(user.id, from, to, auth_method)
  end

  def relays_quota(_root, _args, %{context: %{auth: %{current_user: user}}}) do
    {:ok, Sanbase.WalletHunters.RelayQuota.relays_quota(user.id)}
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
    User.by_selector(selector)
  end

  def following(%User{id: user_id}, _args, _resolution) do
    following = UserFollower.followed_by(user_id)

    {:ok, %{count: length(following), users: following}}
  end

  def following2(%User{id: user_id}, _args, _resolution) do
    following = UserFollower.followed_by2(user_id)

    {:ok, %{count: length(following), users: following}}
  end

  def followers(%User{id: user_id}, _args, _resolution) do
    followers = UserFollower.followers_of(user_id)

    {:ok, %{count: length(followers), users: followers}}
  end

  def followers2(%User{id: user_id}, _args, _resolution) do
    followers = UserFollower.followers_of2(user_id)

    {:ok, %{count: length(followers), users: followers}}
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
        {:error, message: message, details: changeset_errors(changeset)}
    end
  end

  def email_change_verify(
        %{token: email_candidate_token, email_candidate: email_candidate},
        %{context: %{device_data: device_data}}
      ) do
    with {:ok, user} <- User.find_by_email_candidate(email_candidate, email_candidate_token),
         true <- User.email_candidate_token_valid?(user, email_candidate_token),
         {:ok, jwt_tokens} <-
           SanbaseWeb.Guardian.get_jwt_tokens(user,
             platform: device_data.platform,
             client: device_data.client
           ),
         {:ok, user} <- User.update_email_from_email_candidate(user) do
      {:ok,
       %{
         user: user,
         token: jwt_tokens.access_token,
         access_token: jwt_tokens.access_token,
         refresh_token: jwt_tokens.refresh_token
       }}
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
          details: changeset_errors(changeset)
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
          message: "Cannot change the avatar", details: changeset_errors(changeset)
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
    |> Sanbase.Repo.update()
    |> case do
      {:ok, user} ->
        {:ok, user}

      {:error, changeset} ->
        {
          :error,
          message: "Cannot update current user's terms and conditions",
          details: changeset_errors(changeset)
        }
    end
  end

  def user_no_preloads(%{user_id: user_id}, _args, %{context: %{loader: loader}}) do
    loader
    |> Dataloader.load(SanbaseDataloader, :users_by_id, user_id)
    |> on_load(fn loader ->
      {:ok, Dataloader.get(loader, SanbaseDataloader, :users_by_id, user_id)}
    end)
  end
end
