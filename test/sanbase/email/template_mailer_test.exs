defmodule Sanbase.TemplateMailerTest do
  use Sanbase.DataCase

  import Mock

  alias Sanbase.TemplateMailer
  alias Sanbase.Email

  describe "send/3 with exclusion list" do
    test "sends email when recipient is not excluded" do
      email = "allowed@example.com"

      # Ensure email is not excluded
      refute Email.email_excluded?(email)

      # Mock the SimpleMailer to avoid actual email sending
      with_mock Sanbase.SimpleMailer, send_email: fn _, _, _ -> {:ok, :mocked_result} end do
        result =
          TemplateMailer.send(email, "sanbase-sign-in-mail", %{login_link: "http://example.com"})

        # Should call the mocked SimpleMailer and return its result
        assert result == {:ok, :mocked_result}

        # Verify that SimpleMailer.send_email was called
        assert_called(Sanbase.SimpleMailer.send_email(:_, :_, :_))
      end
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

      # No need to mock since this email is excluded and won't reach SimpleMailer
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
