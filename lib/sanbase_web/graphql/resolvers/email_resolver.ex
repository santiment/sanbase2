defmodule SanbaseWeb.Graphql.Resolvers.EmailResolver do
  alias Sanbase.Accounts.NewsletterVerifyAttempt
  alias Sanbase.Email.NewsletterToken
  alias Sanbase.Repo

  # Two-key advisory lock namespaces, distinct from the billing locks (8412, 8413).
  @ip_lock_namespace 8414
  @email_lock_namespace 8415

  def verify_email_newsletter(_root, %{email: email}, resolution) do
    remote_ip = Sanbase.Utils.IP.ip_tuple_to_string(resolution.context.remote_ip)
    email = String.trim(email)

    # The mutation is public and sends an email to an arbitrary address, so it
    # is limited per IP and per recipient. The email is sent after the token is
    # committed, so the locks are not held during the mailer call.
    with {:ok, %NewsletterToken{} = newsletter_token} <-
           create_token_within_limits(email, remote_ip),
         {:ok, _} <- NewsletterToken.send_email(newsletter_token) do
      {:ok, true}
    else
      {:error, :too_many_attempts} -> {:error, "Too many requests, try again after a few minutes"}
      _ -> {:error, "Can't subscribe email: #{email} to newsletter."}
    end
  end

  def subscribe_email_newsletter(_root, %{token: token, email: email, type: _type}, _resolution) do
    with {:ok, _} <- NewsletterToken.verify_token(email, token) do
      {:ok, true}
    else
      {:error, :newsletter_token_invalid} -> {:error, "Verification token is not valid"}
      {:error, :newsletter_token_expired} -> {:error, "Verification token expired"}
      {:error, _} -> {:error, "Can't subscribe email: #{email} to newsletter."}
    end
  end

  # The limits are check-then-insert, so concurrent requests are serialized on
  # the IP and on the recipient with transaction-scoped advisory locks. Without
  # them, parallel requests all pass the checks before any of them inserts.
  # The try variant does not wait: a request that finds either lock taken is
  # rejected at once, so a flood of parallel requests cannot queue up and hold
  # DB pool connections while waiting.
  defp create_token_within_limits(email, remote_ip) do
    Repo.transaction(fn ->
      with true <- try_lock(@ip_lock_namespace, remote_ip),
           true <- try_lock(@email_lock_namespace, String.downcase(email)),
           :ok <- NewsletterVerifyAttempt.check_ip_attempt_limit(remote_ip),
           false <- NewsletterToken.generation_limit_reached?(email),
           {:ok, _} <- NewsletterVerifyAttempt.create(remote_ip),
           {:ok, %NewsletterToken{} = newsletter_token} <-
             NewsletterToken.create_email_token(email) do
        newsletter_token
      else
        # A lock held by a concurrent request, or a limit reached.
        bool when is_boolean(bool) -> Repo.rollback(:too_many_attempts)
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp try_lock(namespace, key) do
    %{rows: [[locked?]]} =
      Repo.query!("SELECT pg_try_advisory_xact_lock($1, hashtext($2))", [namespace, key])

    locked?
  end
end
