defmodule SanbaseWeb.Graphql.Resolvers.EmailResolver do
  alias Sanbase.Accounts.NewsletterVerifyAttempt
  alias Sanbase.Email.NewsletterToken

  def verify_email_newsletter(_root, %{email: email}, resolution) do
    remote_ip = Sanbase.Utils.IP.ip_tuple_to_string(resolution.context.remote_ip)
    email = String.trim(email)

    # The mutation is public and sends an email to an arbitrary address, so it
    # is limited per IP and per recipient.
    with :ok <- NewsletterVerifyAttempt.check_ip_attempt_limit(remote_ip),
         false <- NewsletterToken.recently_generated?(email),
         {:ok, _} <- NewsletterVerifyAttempt.create(remote_ip),
         {:ok, %NewsletterToken{} = newsletter_token} <-
           NewsletterToken.create_email_token(email),
         {:ok, _} <- NewsletterToken.send_email(newsletter_token) do
      {:ok, true}
    else
      {:error, :too_many_attempts} -> {:error, "Too many requests, try again after a few minutes"}
      true -> {:error, "Too many requests, try again after a few minutes"}
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
end
