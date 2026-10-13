defmodule SanbaseWeb.Graphql.EmailNewsletterInvalidEmailTest do
  # Malformed emails crashed the MIME encoding of the "To" header
  use SanbaseWeb.ConnCase, async: false

  import Mock
  import SanbaseWeb.Graphql.TestHelpers

  alias Sanbase.Email.NewsletterToken

  @invalid_emails ["foo@", "foo", "foo@bar.com,", "foo.@bar.com"]

  setup_with_mocks([
    {Swoosh.Adapters.AmazonSES, [],
     [
       validate_config: fn _config -> :ok end,
       deliver: fn email, _config ->
         _raw = Swoosh.Adapters.SMTP.Helpers.body(email, keep_bcc: true)
         {:ok, %{id: "mocked-message-id"}}
       end
     ]}
  ]) do
    :ok
  end

  test "a valid email is accepted and goes through the MIME encoding", %{conn: conn} do
    res = execute_mutation(conn, verify_email_query("test@example.com"), "verifyEmailNewsletter")

    assert res == true
    assert_called_exactly(Swoosh.Adapters.AmazonSES.deliver(:_, :_), 1)
  end

  for email <- @invalid_emails do
    test "verifyEmailNewsletter rejects the malformed email #{inspect(email)}", %{conn: conn} do
      email = unquote(email)

      error_message = execute_mutation_with_error(conn, verify_email_query(email))

      assert error_message =~ "Can't subscribe email"
      assert Sanbase.Repo.get_by(NewsletterToken, email: email) == nil
      assert_not_called(Swoosh.Adapters.AmazonSES.deliver(:_, :_))
    end
  end

  # Records stored before the changeset validated emails still reach the mailer
  for recipient <- ["" | @invalid_emails] do
    test "SimpleMailer.send_email/3 refuses the malformed recipient #{inspect(recipient)}" do
      assert {:error, :invalid_email} =
               Sanbase.SimpleMailer.send_email(unquote(recipient), "Subject", "Body")

      assert_not_called(Swoosh.Adapters.AmazonSES.deliver(:_, :_))
    end
  end

  defp verify_email_query(email) do
    """
    mutation {
      verifyEmailNewsletter(email: "#{email}")
    }
    """
  end
end
