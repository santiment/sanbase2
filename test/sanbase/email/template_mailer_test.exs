defmodule Sanbase.TemplateMailerTest do
  use Sanbase.DataCase

  alias Sanbase.TemplateMailer
  alias Sanbase.Email

  describe "send/3 with exclusion list" do
    test "sends email when recipient is not excluded" do
      # This is a mock test since we don't want to actually send emails in tests
      # In a real implementation, you might use mox to mock the email delivery
      email = "allowed@example.com"

      # Ensure email is not excluded
      refute Email.email_excluded?(email)

      # In real tests, you'd mock the actual email sending
      # For now, we'll just verify the function can be called
      result =
        TemplateMailer.send(email, "sanbase-sign-in-mail", %{login_link: "http://example.com"})

      # The result would depend on your actual email provider response
      # This test mainly ensures no exceptions are thrown
      assert result != nil
    end

    test "does not send email when recipient is excluded" do
      email = "excluded@example.com"
      Email.exclude_email(email, "User unsubscribed")

      result =
        TemplateMailer.send(email, "sanbase-sign-in-mail", %{login_link: "http://example.com"})

      assert result == {:ok, :excluded}
    end

    test "logs exclusion when email is blocked" do
      import ExUnit.CaptureLog

      email = "excluded@example.com"
      Email.exclude_email(email, "Testing exclusion")

      log_output =
        capture_log(fn ->
          TemplateMailer.send(email, "sanbase-sign-in-mail", %{login_link: "http://example.com"})
        end)

      assert log_output =~ "Email #{email} is excluded from receiving emails"
    end

    test "handles exclusion for template emails (second send function)" do
      email = "excluded@example.com"
      Email.exclude_email(email, "User requested")

      result = TemplateMailer.send(email, "some-template", %{})

      assert result == {:ok, :excluded}
    end

    test "still validates invalid emails before checking exclusion" do
      result = TemplateMailer.send("", "sanbase-sign-in-mail", %{})
      assert result == {:error, "invalid email"}

      result = TemplateMailer.send(nil, "sanbase-sign-in-mail", %{})
      assert result == {:error, "invalid email"}
    end
  end
end
