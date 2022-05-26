defmodule SanbaseWeb.Graphql.EmailSubscribeApiTest do
  use SanbaseWeb.ConnCase, async: false

  import Mock
  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  setup_with_mocks([
    {Sanbase.MandrillApi, [:passthrough], send: fn _, _, _ -> {:ok, %{"status" => "sent"}} end},
    {Sanbase.Email.MailchimpApi, [:passthrough], add_email_to_mailchimp: fn _ -> :ok end}
  ]) do
    {:ok, email: "test@example.com"}
  end

  test "verify email for newsletter subscription", context do
    mutation = verify_email_query(context.email)
    res = execute_mutation(context.conn, mutation, "verifyEmailNewsletter")

    assert res == true
  end

  test "subscribe email to newsletter", context do
    nt = insert(:newsletter_token)

    mutation = subscribe_email_query(nt.token, nt.email)
    res = execute_mutation(context.conn, mutation, "subscribeEmailNewsletter")

    assert res == true
  end

  defp verify_email_query(email) do
    """
    mutation {
      verifyEmailNewsletter(email:"#{email}")
    }
    """
  end

  defp subscribe_email_query(token, email) do
    """
    mutation {
      subscribeEmailNewsletter(token: "#{token}", email: "#{email}")
    }
    """
  end
end
