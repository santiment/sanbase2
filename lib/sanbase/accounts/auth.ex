defmodule Sanbase.Accounts.Auth do
  @moduledoc ~s"""
  Orchestrates the cross-cutting auth flows: ETH-wallet login, email-link
  login (send + verify), and email-change verification. Each function returns
  the same shape the GraphQL transport layer renders, so resolvers stay thin.
  """

  import Sanbase.Accounts.EventEmitter, only: [emit_event: 3]

  alias Sanbase.Accounts
  alias Sanbase.Accounts.{AccessAttempt, EmailLoginAttempt, EthAccount, Turnstile, User}
  alias Sanbase.InternalServices.Ethauth

  require Logger

  @blocked_domains ["burpcollaborator.net"]

  @type jwt_result :: %{access_token: String.t(), refresh_token: String.t(), user: User.t()}

  @spec eth_login(map(), map()) ::
          {:ok, jwt_result()} | {:error, [message: String.t()]}
  def eth_login(
        %{signature: signature, address: address, message_hash: message_hash} = args,
        %{device_data: device_data, origin_url: origin_url}
      ) do
    event_args = %{login_origin: :eth_login, origin_url: origin_url}

    with true <- address_message_hash(address) == message_hash,
         true <- Ethauth.valid_signature?(address, signature),
         {:ok, user} <- fetch_user(args, EthAccount.by_address(address)),
         first_login? <- User.RegistrationState.first_login?(user, "eth_login"),
         {:ok, jwt_tokens} <- SanbaseWeb.Guardian.get_jwt_tokens(user, device_data),
         {:ok, _, user} <- Accounts.forward_registration(user, "eth_login", event_args) do
      user = %{user | first_login: first_login?}
      emit_event({:ok, user}, :login_user, event_args)

      {:ok, Map.take(jwt_tokens, [:access_token, :refresh_token]) |> Map.put(:user, user)}
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

  @spec send_login_email(map(), map()) ::
          {:ok, %{success: true}} | {:error, [message: String.t()]}
  def send_login_email(
        %{email: email} = args,
        %{origin_url: origin_url, origin_host_parts: origin_host_parts, remote_ip: remote_ip}
      ) do
    remote_ip = Sanbase.Utils.IP.ip_tuple_to_string(remote_ip)

    with :ok <- Turnstile.validate(args[:token], remote_ip),
         true <- allowed_email_domain?(email),
         true <- allowed_origin?(origin_host_parts, origin_url),
         {:ok, %{first_login: first_login} = user} <-
           User.find_or_insert_by(:email, email, %{username: args[:username]}),
         :ok <- EmailLoginAttempt.check_attempt_limit(user, remote_ip),
         {:ok, user} <- User.Email.update_email_token(user, args[:consent]),
         {:ok, _res} <- User.Email.send_login_email(user, first_login, origin_host_parts, args),
         {:ok, %AccessAttempt{}} <- AccessAttempt.create("email_login", user, remote_ip),
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

      {:error, :too_many_attempts} ->
        Logger.info(
          "Login failed: too many login attempts. Email: #{email}, IP Address: #{remote_ip}, Origin URL: #{origin_url}"
        )

        {:error, message: "Too many login attempts, try again after a few minutes"}

      {:error, error} when is_binary(error) ->
        Logger.error(
          "Login failed: #{error}. Email: #{email}, IP Address: #{remote_ip}, Origin URL: #{origin_url}"
        )

        {:error, message: error}

      error ->
        Logger.error(
          "Login failed: unknown error #{inspect(error)}. Email: #{email}, IP Address: #{remote_ip}, Origin URL: #{origin_url}"
        )

        {:error, message: "Can't login"}
    end
  end

  @spec verify_email_login(map(), map()) ::
          {:ok, jwt_result()} | {:error, [message: String.t()]}
  def verify_email_login(%{token: token, email: email}, %{
        device_data: device_data,
        origin_url: origin_url
      }) do
    args = %{login_origin: :email, origin_url: origin_url}
    rand_id = :crypto.strong_rand_bytes(8) |> Base.encode32(case: :lower) |> binary_part(0, 10)

    Logger.info(
      "[EmailLoginVerify][#{rand_id}] Start verification for #{email} with token #{String.slice(token, 0..5)}"
    )

    with {:ok, user} <- User.find_or_insert_by(:email, email),
         _ <- Logger.info("[EmailLoginVerify][#{rand_id}] Found user with email #{email}"),
         first_login? <- User.RegistrationState.first_login?(user, "email_login_verify"),
         true <- User.Email.email_token_valid?(user, token),
         _ <-
           Logger.info(
             "[EmailLoginVerify][#{rand_id}] Verified token #{String.slice(token, 0..5)} for email #{email}"
           ),
         {:ok, jwt_tokens_map} <- SanbaseWeb.Guardian.get_jwt_tokens(user, device_data),
         _ <-
           Logger.info("[EmailLoginVerify][#{rand_id}] Created JWT tokens map for #{email}"),
         {:ok, user} <- User.Email.mark_email_token_as_validated(user),
         _ <-
           Logger.info(
             "[EmailLoginVerify][#{rand_id}] Marked login token for email #{email} as validated"
           ),
         {:ok, _, user} <- Accounts.forward_registration(user, "email_login_verify", args),
         _ <-
           Logger.info(
             "[EmailLoginVerify][#{rand_id}] Updated the registration state for email #{email}"
           ) do
      Logger.info(
        "[EmailLoginVerify][#{rand_id} Successfully logged in user with email #{email}]"
      )

      user = %{user | first_login: first_login?}
      emit_event({:ok, user}, :login_user, args)

      {:ok, Map.take(jwt_tokens_map, [:access_token, :refresh_token]) |> Map.put(:user, user)}
    else
      _ -> {:error, message: "Email Login verification failed"}
    end
  end

  @spec change_email_request(User.t(), String.t(), tuple()) ::
          {:ok, %{success: true}} | {:error, [message: String.t()]}
  def change_email_request(%User{} = user, email_candidate, remote_ip) do
    remote_ip = Sanbase.Utils.IP.ip_tuple_to_string(remote_ip)

    with :ok <- EmailLoginAttempt.check_attempt_limit(user, remote_ip),
         {:ok, user} <- User.Email.update_email_candidate(user, email_candidate),
         {:ok, _user} <- User.Email.send_verify_email(user),
         {:ok, _} <- EmailLoginAttempt.create(user, remote_ip) do
      {:ok, %{success: true}}
    else
      {:error, error} ->
        error_msg = "Can't change current user's email to #{email_candidate}"
        Logger.info(error_msg <> ". Reason: #{inspect(error)}")
        {:error, message: error_msg}
    end
  end

  @spec verify_email_change(map(), map()) ::
          {:ok, jwt_result()} | {:error, [message: String.t()]}
  def verify_email_change(
        %{token: email_candidate_token, email_candidate: email_candidate},
        %{device_data: device_data}
      ) do
    with {:ok, user} <-
           User.Email.find_by_email_candidate(email_candidate, email_candidate_token),
         true <- User.Email.email_candidate_token_valid?(user, email_candidate_token),
         {:ok, jwt_tokens} <- SanbaseWeb.Guardian.get_jwt_tokens(user, device_data),
         {:ok, user} <- User.Email.update_email_from_email_candidate(user) do
      {:ok, Map.take(jwt_tokens, [:access_token, :refresh_token]) |> Map.put(:user, user)}
    else
      _ -> {:error, message: "Email change verify failed"}
    end
  end

  defp allowed_origin?(["santiment", "net"], _origin_url), do: true
  defp allowed_origin?([_origin_app, "santiment", "net"], _origin_url), do: true

  defp allowed_origin?(_hosted_parts, origin_url),
    do: {:error, "Origin header #{origin_url} is not supported."}

  defp allowed_email_domain?(email) do
    domain = String.split(email, "@") |> Enum.at(1)

    if domain in @blocked_domains do
      {:error, "Email not supported."}
    else
      true
    end
  end

  defp fetch_user(%{address: address}, nil) do
    Accounts.create_user_with_eth_address(address)
  end

  defp fetch_user(_args, %EthAccount{user_id: user_id}) do
    User.by_id(user_id)
  end

  defp address_message_hash(address) do
    message = "Login in Santiment with address #{address}"
    full_message = "\x19Ethereum Signed Message:\n" <> "#{String.length(message)}" <> message
    hash = ExKeccak.hash_256(full_message)
    "0x" <> Base.encode16(hash, case: :lower)
  end
end
