defmodule Sanbase.Email.NewsletterTokenTest do
  use Sanbase.DataCase, async: true

  import Sanbase.Factory

  alias Sanbase.Email.NewsletterToken

  describe "#verify_token" do
    test "successful validation" do
      nt = insert(:newsletter_token)

      {:ok, nt2} = NewsletterToken.verify_token(nt.email, nt.token)
      assert Timex.diff(Timex.now(), nt2.email_token_validated_at, :seconds) <= 1
    end

    test "expired token" do
      nt =
        insert(:newsletter_token, email_token_generated_at: Sanbase.Utils.DateTime.hours_ago(25))

      assert NewsletterToken.verify_token(nt.email, nt.token) ==
               {:error, :newsletter_token_expired}
    end

    test "invalid token" do
      nt = insert(:newsletter_token)

      assert NewsletterToken.verify_token(nt.email, "invalid token") ==
               {:error, :newsletter_token_invalid}
    end
  end
end
