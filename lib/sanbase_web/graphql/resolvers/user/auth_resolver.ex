defmodule SanbaseWeb.Graphql.Resolvers.AuthResolver do
  import Sanbase.Accounts.EventEmitter, only: [emit_event: 3]

  alias Sanbase.InternalServices.Ethauth
  alias Sanbase.Accounts
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
        %{context: %{device_data: device_data, origin_url: origin_url}}
      ) do
    event_args = %{login_origin: :eth_login, origin_url: origin_url}

    with true <- address_message_hash(address) == message_hash,
         true <- Ethauth.valid_signature?(address, signature),
         {:ok, user} <- fetch_user(args, EthAccount.by_address(address)),
         first_login? <- User.RegistrationState.first_login?(user, "eth_login"),
         {:ok, jwt_tokens} <- SanbaseWeb.Guardian.get_jwt_tokens(user, device_data),
         {:ok, _, user} <- Sanbase.Accounts.forward_registration(user, "eth_login", event_args) do
      user = %{user | first_login: first_login?}
      emit_event({:ok, user}, :login_user, event_args)

      result = Map.take(jwt_tokens, [:access_token, :refresh_token]) |> Map.put(:user, user)

      {:ok, result}
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        Logger.warning("Login failed: #{inspect(changeset)}")
        {:error, message: "Wallet Login verification failed"}

      {:error, reason} ->
        Logger.warning("Login failed: #{inspect(reason)}")
        {:error, message: "Wallet Login verification failed"}

      _ ->
        Logger.warning("Login failed: invalid signature")
        {:error, message: "Wallet Login verification failed"}
    end
  end

  def send_email_login_email(%{email: email} = args, %{
        context: %{
          origin_url: origin_url,
          origin_host_parts: origin_host_parts,
          remote_ip: remote_ip
        }
      }) do
    remote_ip = Sanbase.Utils.IP.ip_tuple_to_string(remote_ip)

    with true <- allowed_email_domain?(email),
         true <- allowed_origin?(origin_host_parts, origin_url),
         {:ok, %{first_login: first_login} = user} <-
           User.find_or_insert_by(:email, email, %{username: args[:username]}),
         :ok <- EmailLoginAttempt.has_allowed_login_attempts(user, remote_ip),
         {:ok, user} <- User.Email.update_email_token(user, args[:consent]),
         {:ok, _res} <- User.Email.send_login_email(user, first_login, origin_host_parts, args),
         {:ok, %EmailLoginAttempt{}} <- EmailLoginAttempt.create(user, remote_ip),
         {:ok, _, user} <-
           Accounts.forward_registration(user, "send_login_email", %{"origin_url" => origin_url}) do
      emit_event({:ok, user}, :send_email_login_link, %{origin_url: origin_url})

      {:ok, %{success: true}}
    else
      {:error, :invalid_redirect_url, message} ->
        Logger.error(
          "Login failed: #{message}. Email: #{email}, IP Address: #{remote_ip}, Origin URL: #{origin_url}"
        )

        {:error, message: message}

      {:error, :too_many_login_attempts} ->
        Logger.info(
          "Login failed: too many login attempts. Email: #{email}, IP Address: #{remote_ip}, Origin URL: #{origin_url}"
        )

        {:error, message: "Too many login attempts, try again after a few minutes"}

      error ->
        Logger.error(
          "Login failed: unknown error #{inspect(error)}. Email: #{email}, IP Address: #{remote_ip}, Origin URL: #{origin_url}"
        )

        {:error, message: "Can't login"}
    end
  end

  def email_login_verify(%{token: token, email: email}, %{
        context: %{device_data: device_data, origin_url: origin_url}
      }) do
    args = %{login_origin: :email, origin_url: origin_url}

    with {:ok, user} <- User.find_or_insert_by(:email, email),
         first_login? <- User.RegistrationState.first_login?(user, "email_login_verify"),
         true <- User.Email.email_token_valid?(user, token),
         {:ok, jwt_tokens_map} <- SanbaseWeb.Guardian.get_jwt_tokens(user, device_data),
         {:ok, user} <- User.Email.mark_email_token_as_validated(user),
         {:ok, _, user} <- Accounts.forward_registration(user, "email_login_verify", args) do
      user = %{user | first_login: first_login?}
      emit_event({:ok, user}, :login_user, args)

      result = Map.take(jwt_tokens_map, [:access_token, :refresh_token]) |> Map.put(:user, user)

      {:ok, result}
    else
      _ -> {:error, message: "Email Login verification failed"}
    end
  end

  # Use the same rate limit as logins to track amount of emails send
  # for email change
  def change_email(_root, %{email: email_candidate}, %{
        context: %{
          remote_ip: remote_ip,
          auth: %{auth_method: :user_token, current_user: user}
        }
      }) do
    remote_ip = Sanbase.Utils.IP.ip_tuple_to_string(remote_ip)

    with :ok <- EmailLoginAttempt.has_allowed_login_attempts(user, remote_ip),
         {:ok, user} <- User.Email.update_email_candidate(user, email_candidate),
         {:ok, _user} <- User.Email.send_verify_email(user),
         {:ok, %EmailLoginAttempt{}} <- EmailLoginAttempt.create(user, remote_ip) do
      {:ok, %{success: true}}
    else
      {:error, error} ->
        error_msg = "Can't change current user's email to #{email_candidate}"
        Logger.info(error_msg <> ". Reason: #{inspect(error)}")
        {:error, message: error_msg}
    end
  end

  def email_change_verify(
        %{token: email_candidate_token, email_candidate: email_candidate},
        %{context: %{device_data: device_data}}
      ) do
    with {:ok, user} <-
           User.Email.find_by_email_candidate(email_candidate, email_candidate_token),
         true <- User.Email.email_candidate_token_valid?(user, email_candidate_token),
         {:ok, jwt_tokens} <- SanbaseWeb.Guardian.get_jwt_tokens(user, device_data),
         {:ok, user} <- User.Email.update_email_from_email_candidate(user) do
      result = Map.take(jwt_tokens, [:access_token, :refresh_token]) |> Map.put(:user, user)

      {:ok, result}
    else
      _ -> {:error, message: "Email change verify failed"}
    end
  end

  defp allowed_origin?(["santiment", "net"] = _hosted_parts, _origin_url), do: true
  defp allowed_origin?([_origin_app, "santiment", "net"] = _hosted_parts, _origin_url), do: true

  defp allowed_origin?(_hosted_parts, origin_url),
    do: {:error, "Origin header #{origin_url} is not supported."}

  @blocked_domains ["burpcollaborator.net"]
  defp allowed_email_domain?(email) do
    domain = String.split(email, "@") |> Enum.at(1)

    case domain in @blocked_domains do
      true -> {:error, "Email not supported."}
      false -> true
    end
  end

  defp fetch_user(%{address: address}, nil) do
    # No EthAccount and no user logged in. This means that the address is used
    # for the first time. Create a User and create an EthAccount linked with
    # the user. The username is automatically set to the address but is not
    # used for logging in after that.
    Accounts.create_user_with_eth_address(address)
  end

  defp fetch_user(_args, %EthAccount{user_id: user_id}) do
    # Existing EthAccount, login as the user of EthAccount
    User.by_id(user_id)
  end

  defp address_message_hash(address) do
    message = "Login in Santiment with address #{address}"
    full_message = "\x19Ethereum Signed Message:\n" <> "#{String.length(message)}" <> message
    hash = ExKeccak.hash_256(full_message)
    "0x" <> Base.encode16(hash, case: :lower)
  end
end
