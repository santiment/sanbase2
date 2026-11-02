defmodule Sanbase.Accounts.Auth do
  @moduledoc ~s"""
  Login and email-change flows. Errors are `{:error, user_facing_message}`.

  Flows that log a user in take an `issue_tokens` function
  (`user -> {:ok, %{access_token: _, refresh_token: _}}`) from the caller. It is
  called before a one-time email token is consumed, so a failure leaves the
  link usable.
  """

  import Sanbase.Accounts.EventEmitter, only: [emit_event: 3]

  alias Sanbase.Accounts

  alias Sanbase.Accounts.{
    AccessAttempt,
    EmailLoginAttempt,
    EthAccount,
    EthLoginChallenge,
    Turnstile,
    User
  }

  alias Sanbase.FeatureToggle
  alias Sanbase.InternalServices.Ethauth

  require Logger

  @blocked_domains ["burpcollaborator.net"]

  @doc ~s"""
  Log in with a wallet signature.

  Two ways to prove the wallet:
    - `nonce` given: the wallet signed the message of a challenge from
      `Sanbase.Accounts.EthLoginChallenge.create/1`. The nonce works once and
      expires, so a captured signature cannot be replayed.
    - no `nonce` (legacy): the wallet signed the fixed text "Login in Santiment
      with address X". Such a signature never expires. Accepted only while the
      `eth_login_legacy` feature toggle is enabled.
  """
  def eth_login(
        %{signature: _, address: address} = args,
        %{issue_tokens: issue_tokens, origin_url: origin_url}
      ) do
    event_args = %{login_origin: :eth_login, origin_url: origin_url}

    with :ok <- verify_wallet_signature(args),
         {:ok, user} <- fetch_user(args, EthAccount.by_address(address)),
         first_login? <- User.RegistrationState.first_login?(user, "eth_login"),
         {:ok, tokens} <- issue_tokens.(user),
         {:ok, _, user} <- Accounts.forward_registration(user, "eth_login", event_args) do
      user = %{user | first_login: first_login?}
      emit_event({:ok, user}, :login_user, event_args)

      {:ok, Map.take(tokens, [:access_token, :refresh_token]) |> Map.put(:user, user)}
    else
      {:error, :registrations_disabled} ->
        Logger.info("Wallet login rejected: registrations are disabled. Address: #{address}")
        {:error, "New registrations are temporarily disabled."}

      {:error, %Ecto.Changeset{} = changeset} ->
        Logger.warning("Login failed: #{inspect(changeset)}")
        {:error, "Wallet Login verification failed"}

      {:error, reason} ->
        Logger.warning("Login failed: #{inspect(reason)}")
        {:error, "Wallet Login verification failed"}

      _ ->
        Logger.warning("Login failed: invalid signature")
        {:error, "Wallet Login verification failed"}
    end
  end

  def send_login_email(
        %{email: email} = args,
        %{origin_url: origin_url, origin_host_parts: origin_host_parts, remote_ip: remote_ip}
      ) do
    remote_ip = Sanbase.Utils.IP.ip_tuple_to_string(remote_ip)

    with :ok <- Turnstile.validate(args[:token], remote_ip),
         true <- allowed_email_domain?(email),
         true <- allowed_origin?(origin_host_parts, origin_url),
         :ok <- EmailLoginAttempt.check_ip_attempt_limit(remote_ip),
         {:ok, %{first_login: first_login} = user} <-
           User.find_or_insert_by(:email, email, %{username: args[:username]}),
         :ok <- EmailLoginAttempt.check_attempt_limit(user, remote_ip),
         {:ok, user} <-
           User.Email.update_email_token(
             user,
             args[:consent],
             args[:subscribe_to_weekly_newsletter]
           ),
         {:ok, _res} <- User.Email.send_login_email(user, first_login, origin_host_parts, args),
         {:ok, %AccessAttempt{}} <- AccessAttempt.create("email_login", user, remote_ip),
         {:ok, _, user} <-
           Accounts.forward_registration(user, "send_login_email", %{"origin_url" => origin_url}) do
      emit_event({:ok, user}, :send_email_login_link, %{origin_url: origin_url})
      {:ok, %{success: true}}
    else
      {:error, :registrations_disabled} ->
        # Answer as if the email was sent, so the response does not reveal which
        # emails have an account. No user is created and no email is sent.
        Logger.info(
          "Login email not sent: registrations are disabled. Email: #{email}, IP Address: #{remote_ip}, Origin URL: #{origin_url}"
        )

        {:ok, %{success: true}}

      {:error, :invalid_redirect_url, message} ->
        Logger.error(
          "Login failed: #{message}. Email: #{email}, IP Address: #{remote_ip}, Origin URL: #{origin_url}"
        )

        {:error, message}

      {:error, :too_many_attempts} ->
        Logger.info(
          "Login failed: too many login attempts. Email: #{email}, IP Address: #{remote_ip}, Origin URL: #{origin_url}"
        )

        {:error, "Too many login attempts, try again after a few minutes"}

      {:error, error} when is_binary(error) ->
        Logger.error(
          "Login failed: #{error}. Email: #{email}, IP Address: #{remote_ip}, Origin URL: #{origin_url}"
        )

        {:error, error}

      error ->
        Logger.error(
          "Login failed: unknown error #{inspect(error)}. Email: #{email}, IP Address: #{remote_ip}, Origin URL: #{origin_url}"
        )

        {:error, "Can't login"}
    end
  end

  def verify_email_login(%{token: token, email: email}, %{
        issue_tokens: issue_tokens,
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
         {:ok, tokens} <- issue_tokens.(user),
         _ <- Logger.info("[EmailLoginVerify][#{rand_id}] Issued session tokens for #{email}"),
         {:ok, user} <- User.Email.mark_email_token_as_validated(user),
         _ <-
           Logger.info(
             "[EmailLoginVerify][#{rand_id}] Marked login token for email #{email} as validated"
           ),
         {:ok, user} <- Accounts.confirm_newsletter_opt_in(user),
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

      {:ok, Map.take(tokens, [:access_token, :refresh_token]) |> Map.put(:user, user)}
    else
      _ -> {:error, "Email Login verification failed"}
    end
  end

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
        {:error, error_msg}
    end
  end

  def verify_email_change(
        %{token: email_candidate_token, email_candidate: email_candidate},
        %{issue_tokens: issue_tokens}
      ) do
    with {:ok, user} <-
           User.Email.find_by_email_candidate(email_candidate, email_candidate_token),
         true <- User.Email.email_candidate_token_valid?(user, email_candidate_token),
         {:ok, tokens} <- issue_tokens.(user),
         {:ok, user} <- User.Email.update_email_from_email_candidate(user) do
      {:ok, Map.take(tokens, [:access_token, :refresh_token]) |> Map.put(:user, user)}
    else
      _ -> {:error, "Email change verify failed"}
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

  defp verify_wallet_signature(%{nonce: nonce, address: address, signature: signature})
       when is_binary(nonce) do
    # Check the signature before using up the nonce, so a wrong signature does not
    # burn it. `consume/2` is atomic, so of two requests with the same valid
    # signature only one logs in.
    with {:ok, message} <- EthLoginChallenge.get_open(address, nonce),
         true <- Ethauth.valid_signature?(address, signature, message),
         :ok <- EthLoginChallenge.consume(address, nonce) do
      :ok
    end
  end

  defp verify_wallet_signature(%{address: address, signature: signature} = args) do
    message_hash = Map.get(args, :message_hash)

    cond do
      not FeatureToggle.eth_login_legacy_enabled?() ->
        {:error, :legacy_eth_login_disabled}

      address_message_hash(address) != message_hash ->
        false

      true ->
        case Ethauth.valid_signature?(address, signature) do
          true -> :ok
          other -> other
        end
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
