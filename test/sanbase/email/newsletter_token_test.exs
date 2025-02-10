defmodule Sanbase.Email.NewsletterTokenTest do
  use Sanbase.DataCase, async: false

  import Sanbase.Factory

  alias Sanbase.DateTimeUtils
  alias Sanbase.Email.NewsletterToken

  describe "#verify_token" do
    test "successful validation" do
      nt = insert(:newsletter_token)

      {:ok, nt2} = NewsletterToken.verify_token(nt.email, nt.token)
      assert Timex.diff(DateTime.utc_now(), nt2.email_token_validated_at, :seconds) <= 1
    end

    test "expired token" do
      nt = insert(:newsletter_token, email_token_generated_at: DateTimeUtils.hours_ago(25))

      assert NewsletterToken.verify_token(nt.email, nt.token) == {:error, :expired_token}
    end

    test "invalid token" do
      nt = insert(:newsletter_token)

      assert NewsletterToken.verify_token(nt.email, "invalid token") == {:error, :invalid_token}
    end
  end
end
