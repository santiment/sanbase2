defmodule SanbaseWeb.Graphql.Resolvers.EmailResolver do
  alias Sanbase.Email.NewsletterToken

  def verify_email_newsletter(_root, %{email: email}, _resolution) do
    with {:ok, %NewsletterToken{} = newsletter_token} <-
           NewsletterToken.create_email_token(email),
         {:ok, _} <- NewsletterToken.send_email(newsletter_token) do
      {:ok, true}
    else
      _ -> {:error, "Can't subscribe email: #{email} to newsletter."}
    end
  end

  def subscribe_email_newsletter(_root, %{token: token, email: email, type: _type}, _resolution) do
    with {:ok, _} <- NewsletterToken.verify_token(email, token) do
      {:ok, true}
    else
      {:error, :invalid_token} -> {:error, "Verification token is not valid"}
      {:error, :token_expired} -> {:error, "Verification token expired"}
    end
  end
end
