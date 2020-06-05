defmodule SanbaseWeb.Graphql.Resolvers.EmailResolver do
  alias Sanbase.Email.Mailchimp

  def subscribe_weekly(_root, %{email: email}, _resolution) do
    case Mailchimp.add_email_to_mailchimp(email) do
      :ok -> {:ok, true}
      {:error, _reason} -> {:error, "Email address #{email} is already subscribed."}
    end
  end
end
