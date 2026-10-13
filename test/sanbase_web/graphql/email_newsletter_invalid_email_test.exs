defmodule SanbaseWeb.Graphql.EmailNewsletterInvalidEmailTest do
  use SanbaseWeb.ConnCase, async: false

  import Mock
  import SanbaseWeb.Graphql.TestHelpers

  alias Sanbase.Email.NewsletterToken

  setup_with_mocks([
    {Swoosh.Adapters.AmazonSES, [],
     [
       validate_config: fn _config -> :ok end,
       # Encode the email like the real adapter does, so a bad "To" header still crashes
       deliver: fn email, _config ->
         _raw = Swoosh.Adapters.SMTP.Helpers.body(email, keep_bcc: true)
         {:ok, %{id: "mocked-message-id"}}
       end
     ]}
  ]) do
    :ok
  end

  test "a valid email is accepted and sent", %{conn: conn} do
    res = execute_mutation(conn, verify_email_query("test@example.com"), "verifyEmailNewsletter")

    assert res == true
    assert_called_exactly(Swoosh.Adapters.AmazonSES.deliver(:_, :_), 1)
  end

  # "foo.@bar.com" passes the email regex but not the "To" header parser
  for email <- ["foo", "foo.@bar.com"] do
    test "verifyEmailNewsletter rejects the malformed email #{inspect(email)}", %{conn: conn} do
      email = unquote(email)

      error_message = execute_mutation_with_error(conn, verify_email_query(email))

      assert error_message =~ "Can't subscribe email"
      assert Sanbase.Repo.get_by(NewsletterToken, email: email) == nil
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
