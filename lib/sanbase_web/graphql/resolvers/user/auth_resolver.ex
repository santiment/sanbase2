defmodule SanbaseWeb.Graphql.Resolvers.AuthResolver do
  import Sanbase.Accounts.EventEmitter, only: [emit_event: 3]

  alias Sanbase.InternalServices.Ethauth
  alias Sanbase.Accounts.{User, EthAccount, EmailLoginAttempt}

  require Logger

  def get_auth_sessions(_root, _args, %{context: %{auth: %{current_user: user}} = context}) do
    refresh_token = context[:jwt_tokens][:refresh_token]

    SanbaseWeb.Guardian.Token.refresh_tokens(user.id, refresh_token)
  end

  def revoke_current_refresh_token(_root, _args, %{context: %{jwt_tokens: jwt_tokens}}) do
    case Map.get(jwt_tokens, :refresh_token) do
      nil ->
        {:ok, true}

      refresh_token ->
        {:ok, _} = SanbaseWeb.Guardian.revoke(refresh_token)
        {:ok, true}
    end
  end

  def revoke_refresh_token(
        _root,
        %{refresh_token_jti: jti},
        %{context: %{auth: %{current_user: user}}}
      ) do
    case SanbaseWeb.Guardian.Token.revoke(jti, user.id) do
      :ok -> {:ok, true}
      _ -> {:ok, false}
    end
  end

  def revoke_all_refresh_tokens(_root, _args, %{context: %{auth: %{current_user: user}}}) do
    case SanbaseWeb.Guardian.Token.revoke_all_with_user_id(user.id) do
      :ok -> {:ok, true}
      _ -> {:error, false}
    end
  end

  def eth_login(
        _root,
        %{signature: signature, address: address, message_hash: message_hash} = args,
        %{context: %{device_data: device_data}}
      ) do
    event_args = %{login_origin: :eth_login}

    with true <- Ethauth.is_valid_signature?(address, signature),
         {:ok, user} <- fetch_user(args, EthAccount.by_address(address)),
         {:ok, %{} = jwt_tokens_map} <-
           SanbaseWeb.Guardian.get_jwt_tokens(user,
             platform: device_data.platform,
             client: device_data.client
           ),
         {:ok, user} <- User.mark_as_registered(user, event_args) do
      emit_event({:ok, user}, :login_user, event_args)

      {:ok,
       %{
         user: user,
         token: jwt_tokens_map.access_token,
         access_token: jwt_tokens_map.access_token,
         refresh_token: jwt_tokens_map.refresh_token
       }}
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
        context: %{
          origin_url: origin_url,
          origin_host_parts: origin_host_parts,
          remote_ip: remote_ip
        }
      }) do
    remote_ip = Sanbase.Utils.IP.ip_tuple_to_string(remote_ip)

    with true <- allowed_origin?(origin_host_parts),
         {:ok, user} <- User.find_or_insert_by(:email, email, %{username: args[:username]}),
         :ok <- EmailLoginAttempt.has_allowed_login_attempts(user, remote_ip),
         {:ok, user} <- User.update_email_token(user, args[:consent]),
         {:ok, _user} <- User.send_login_email(user, origin_host_parts, args),
         {:ok, %EmailLoginAttempt{}} <- EmailLoginAttempt.create(user, remote_ip) do
      {:ok, %{success: true, first_login: user.first_login}}
    else
      {:error, :too_many_login_attempts} ->
        Logger.info(
          "Login failed: too many login attempts. Email: #{email}, IP Address: #{remote_ip}, Origin URL: #{origin_url}"
        )

        {:error, message: "Too many login attempts, try again after a few minutes"}

      _ ->
        {:error, message: "Can't login"}
    end
  end

  def email_login_verify(%{token: token, email: email}, %{context: %{device_data: device_data}}) do
    event_args = %{login_origin: :email}

    with {:ok, user} <- User.find_or_insert_by(:email, email),
         true <- User.email_token_valid?(user, token),
         {:ok, %{} = jwt_tokens_map} <-
           SanbaseWeb.Guardian.get_jwt_tokens(user,
             platform: device_data.platform,
             client: device_data.client
           ),
         {:ok, user} <- User.mark_email_token_as_validated(user),
         {:ok, user} <- User.mark_as_registered(user, event_args) do
      emit_event({:ok, user}, :login_user, event_args)

      {:ok,
       %{
         user: user,
         token: jwt_tokens_map.access_token,
         access_token: jwt_tokens_map.access_token,
         refresh_token: jwt_tokens_map.refresh_token
       }}
    else
      _ -> {:error, message: "Login failed"}
    end
  end

  defp allowed_origin?(["santiment", "net"] = _hosted_parts), do: true
  defp allowed_origin?([_origin_app, "santiment", "net"] = _hosted_parts), do: true
  defp allowed_origin?(_hosted_parts), do: {:error, "Origin header is not supported."}

  defp fetch_user(%{address: address}, nil) do
    # No EthAccount and no user logged in. This means that the address is used
    # for the first time. Create a User and create an EthAccount linked with
    # the user. The username is automatically set to the address but is not
    # used for logging in after that.
    Sanbase.Accounts.create_user_with_eth_address(address)
  end

  defp fetch_user(_args, %EthAccount{user_id: user_id}) do
    # Existing EthAccount, login as the user of EthAccount
    User.by_id(user_id)
  end
end
