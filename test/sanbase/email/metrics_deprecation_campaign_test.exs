defmodule Sanbase.Email.MetricsDeprecationCampaignTest do
  use Sanbase.DataCase, async: false

  import Sanbase.Factory

  alias Sanbase.Email.MetricsDeprecationCampaign

  describe "markdown_to_html/1" do
    test "keeps the Mailjet unsubscribe placeholder as a literal link target" do
      {:ok, html} =
        MetricsDeprecationCampaign.markdown_to_html(
          "You can [unsubscribe here]([[UNSUB_LINK_EN]]) or read [more](https://x.y/%5Ba%5D)."
        )

      assert html =~ ~s(<a href="[[UNSUB_LINK_EN]]">unsubscribe here</a>)
      assert html =~ ~s(<a href="https://x.y/%5Ba%5D">more</a>)
    end
  end

  describe "get_active_sanapi_users/1" do
    setup do
      # `subscription_pro` is plan_id 3, which belongs to the SanAPI product.
      customer = insert_with_subscription(email: "customer@example.com")
      lookalike = insert_with_subscription(email: "customer@notsantiment.net")
      team = insert_with_subscription(email: "someone@santiment.net")
      without_email = insert_with_subscription(email: nil)

      {:ok, customer: customer, lookalike: lookalike, team: team, without_email: without_email}
    end

    test "excludes only the team addresses", context do
      ids = MetricsDeprecationCampaign.get_active_sanapi_users(false) |> Enum.map(& &1.id)

      assert context.customer.id in ids
      # A domain that merely ends with santiment.net is a customer.
      assert context.lookalike.id in ids
      refute context.team.id in ids
    end

    test "a user without an email does not raise", context do
      ids = MetricsDeprecationCampaign.get_active_sanapi_users(false) |> Enum.map(& &1.id)

      # `add_users_to_list/2` drops them later.
      assert context.without_email.id in ids
    end
  end

  defp insert_with_subscription(email: email) do
    user = insert(:user, email: email)
    insert(:subscription_pro, user: user)

    user
  end
end
