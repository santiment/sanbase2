defmodule Sanbase.Accounts.MarketingConsentTest do
  use SanbaseWeb.ConnCase, async: false

  import Mox
  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  alias Sanbase.Accounts
  alias Sanbase.Accounts.{User, UserSettings}
  alias Sanbase.Email.MailjetEventHandler
  alias Sanbase.Repo

  @subscriber Sanbase.EventBus.UserEventsSubscriber

  setup :set_mox_global

  setup do
    Sanbase.EventBus.subscribe_subscriber(@subscriber)

    on_exit(fn ->
      Sanbase.EventBus.drain_topics(@subscriber.topics(), 10_000)
      Sanbase.EventBus.unsubscribe_subscriber(@subscriber)
    end)

    test_pid = self()

    stub(Sanbase.Email.MockMailjetApi, :subscribe, fn list, email ->
      send(test_pid, {:mailjet_subscribe, list, email})
      :ok
    end)

    stub(Sanbase.Email.MockMailjetApi, :unsubscribe, fn list, email ->
      send(test_pid, {:mailjet_unsubscribe, list, email})
      :ok
    end)

    user = insert(:user, email: "consent@example.com", marketing_accepted: false)

    %{user: user}
  end

  describe "update_terms_and_conditions/2" do
    test "accepting marketing syncs the setting and subscribes to the list", %{user: user} do
      assert {:ok, user} = Accounts.update_terms_and_conditions(user, %{marketing_accepted: true})

      assert user.marketing_accepted
      assert UserSettings.settings_for(user).is_subscribed_marketing_emails

      drain_events()
      assert_received {:mailjet_subscribe, :marketing_newsletter, "consent@example.com"}
    end

    test "revoking marketing syncs the setting and unsubscribes from the list", %{user: user} do
      {:ok, user} = Accounts.update_terms_and_conditions(user, %{marketing_accepted: true})
      drain_events()

      assert {:ok, user} =
               Accounts.update_terms_and_conditions(user, %{marketing_accepted: false})

      refute user.marketing_accepted
      refute UserSettings.settings_for(user).is_subscribed_marketing_emails

      drain_events()
      assert_received {:mailjet_unsubscribe, :marketing_newsletter, "consent@example.com"}
    end

    test "writing an unchanged value does not touch Mailjet", %{user: user} do
      assert {:ok, _} =
               Accounts.update_terms_and_conditions(user, %{
                 privacy_policy_accepted: true,
                 marketing_accepted: false
               })

      drain_events()
      refute_received {:mailjet_subscribe, _, _}
      refute_received {:mailjet_unsubscribe, _, _}
    end

    test "updating only the privacy policy does not touch the marketing consent", %{user: user} do
      insert(:user_settings, user: user, settings: %{is_subscribed_marketing_emails: true})

      assert {:ok, user} =
               Accounts.update_terms_and_conditions(user, %{privacy_policy_accepted: true})

      assert user.privacy_policy_accepted
      assert UserSettings.settings_for(user).is_subscribed_marketing_emails

      drain_events()
      refute_received {:mailjet_subscribe, _, _}
      refute_received {:mailjet_unsubscribe, _, _}
    end

    test "accepting marketing subscribes even if the setting was already on", %{user: user} do
      insert(:user_settings, user: user, settings: %{is_subscribed_marketing_emails: true})

      assert {:ok, _} = Accounts.update_terms_and_conditions(user, %{marketing_accepted: true})

      drain_events()
      assert_received {:mailjet_subscribe, :marketing_newsletter, "consent@example.com"}
    end
  end

  describe "is_subscribed_marketing_emails setting" do
    test "turning it on syncs marketing_accepted and subscribes to the list", %{user: user} do
      assert {:ok, _} =
               UserSettings.update_settings(user, %{is_subscribed_marketing_emails: true})

      assert Repo.get!(User, user.id).marketing_accepted

      drain_events()
      assert_received {:mailjet_subscribe, :marketing_newsletter, "consent@example.com"}
    end

    test "turning it off syncs marketing_accepted and unsubscribes from the list", %{user: user} do
      {:ok, user} = Accounts.update_terms_and_conditions(user, %{marketing_accepted: true})
      drain_events()

      assert {:ok, _} =
               UserSettings.update_settings(user, %{is_subscribed_marketing_emails: false})

      refute Repo.get!(User, user.id).marketing_accepted

      drain_events()
      assert_received {:mailjet_unsubscribe, :marketing_newsletter, "consent@example.com"}
    end

    test "updating other settings does not touch the marketing consent", %{user: user} do
      {:ok, user} = Accounts.update_terms_and_conditions(user, %{marketing_accepted: true})
      drain_events()

      assert {:ok, _} = UserSettings.update_settings(user, %{theme: "nightmode"})

      assert Repo.get!(User, user.id).marketing_accepted

      drain_events()
      refute_received {:mailjet_unsubscribe, _, _}
    end
  end

  describe "Mailjet unsubscribe webhook" do
    for {list_name, list_id} <- [
          {"marketing newsletter", "10331431"},
          {"SanR", "10321582"},
          {"Alpha Narratives", "10321590"}
        ] do
      test "unsubscribing from the #{list_name} list revokes the marketing consent", %{
        user: user
      } do
        {:ok, user} = Accounts.update_terms_and_conditions(user, %{marketing_accepted: true})
        drain_events()

        assert {:ok, _} = MailjetEventHandler.handle_unsubscribe(user.email, unquote(list_id))

        refute Repo.get!(User, user.id).marketing_accepted
        refute UserSettings.settings_for(user).is_subscribed_marketing_emails

        drain_events()
        assert_received {:mailjet_unsubscribe, :marketing_newsletter, "consent@example.com"}
      end
    end

    test "unsubscribing a user that has not accepted marketing does not touch Mailjet", %{
      user: user
    } do
      assert {:ok, _} = MailjetEventHandler.handle_unsubscribe(user.email, "10331431")

      refute Repo.get!(User, user.id).marketing_accepted

      drain_events()
      refute_received {:mailjet_unsubscribe, _, _}
    end
  end

  describe "updateTermsAndConditions mutation" do
    test "accepting marketing syncs the setting and subscribes to the list", %{
      conn: conn,
      user: user
    } do
      conn = setup_jwt_auth(conn, user)

      mutation = """
      mutation {
        updateTermsAndConditions(privacyPolicyAccepted: true, marketingAccepted: true) {
          privacyPolicyAccepted
          marketingAccepted
          settings { isSubscribedMarketingEmails }
        }
      }
      """

      result =
        conn
        |> post("/graphql", mutation_skeleton(mutation))
        |> json_response(200)

      assert %{
               "privacyPolicyAccepted" => true,
               "marketingAccepted" => true,
               "settings" => %{"isSubscribedMarketingEmails" => true}
             } = result["data"]["updateTermsAndConditions"]

      drain_events()
      assert_received {:mailjet_subscribe, :marketing_newsletter, "consent@example.com"}
    end
  end

  defp drain_events() do
    Sanbase.EventBus.drain_topics(@subscriber.topics(), 10_000)
  end
end
