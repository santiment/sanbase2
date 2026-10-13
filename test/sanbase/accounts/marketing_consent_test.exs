defmodule Sanbase.Accounts.MarketingConsentTest do
  use SanbaseWeb.ConnCase, async: false

  import Mox
  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  alias Sanbase.Accounts
  alias Sanbase.Accounts.{User, UserSettings}
  alias Sanbase.Email.{ListConsent, MailjetEventHandler}
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
      assert_newsletter_settings(user, true)

      drain_events()
      assert_received {:mailjet_subscribe, :marketing_newsletter, "consent@example.com"}
    end

    test "records the consent from the signup dialog before the privacy policy is accepted" do
      user = insert(:user, email: "signup@example.com", privacy_policy_accepted: false)

      {:ok, _} =
        Accounts.update_terms_and_conditions(user, %{
          privacy_policy_accepted: true,
          marketing_accepted: true
        })

      assert [%ListConsent{subscribed: true, source: :signup_dialog}] =
               ListConsent.history(user.id, :newsletter)
    end

    test "records the consent from the privacy page after the privacy policy is accepted", %{
      user: user
    } do
      {:ok, user} = Accounts.update_terms_and_conditions(user, %{privacy_policy_accepted: true})
      {:ok, _} = Accounts.update_terms_and_conditions(user, %{marketing_accepted: true})

      assert [%ListConsent{subscribed: true, source: :privacy_page}] =
               ListConsent.history(user.id, :newsletter)
    end

    test "an unticked checkbox in the signup dialog does not record anything", %{user: user} do
      user = %{user | privacy_policy_accepted: false}

      assert {:ok, user} =
               Accounts.update_terms_and_conditions(user, %{
                 privacy_policy_accepted: true,
                 marketing_accepted: false
               })

      assert user.privacy_policy_accepted
      refute user.marketing_accepted
      assert [] = ListConsent.history(user.id, :newsletter)
    end

    test "revoking marketing syncs the setting and unsubscribes from the list", %{user: user} do
      {:ok, user} = Accounts.update_terms_and_conditions(user, %{marketing_accepted: true})
      drain_events()

      assert {:ok, user} =
               Accounts.update_terms_and_conditions(user, %{marketing_accepted: false})

      refute user.marketing_accepted
      assert_newsletter_settings(user, false)

      drain_events()
      assert_received {:mailjet_unsubscribe, :marketing_newsletter, "consent@example.com"}

      assert [%ListConsent{subscribed: true}, %ListConsent{subscribed: false}] =
               ListConsent.history(user.id, :newsletter)
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
      assert [] = ListConsent.history(user.id, :newsletter)
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

  describe "is_subscribed_weekly_newsletter setting (Weekly newsletter toggle)" do
    test "is off by default", %{user: user} do
      refute UserSettings.settings_for(user).is_subscribed_weekly_newsletter
    end

    test "turning it on syncs the consent and subscribes to the list", %{user: user} do
      assert {:ok, %{settings: settings}} =
               UserSettings.update_settings(user, %{is_subscribed_weekly_newsletter: true})

      assert settings.is_subscribed_weekly_newsletter
      assert settings.is_subscribed_marketing_emails
      assert Repo.get!(User, user.id).marketing_accepted

      assert [%ListConsent{subscribed: true, source: :settings_toggle}] =
               ListConsent.history(user.id, :newsletter)

      drain_events()
      assert_received {:mailjet_subscribe, :marketing_newsletter, "consent@example.com"}
    end

    test "turning it off syncs the consent and unsubscribes from the list", %{user: user} do
      {:ok, user} = Accounts.update_terms_and_conditions(user, %{marketing_accepted: true})
      drain_events()

      assert {:ok, _} =
               UserSettings.update_settings(user, %{is_subscribed_weekly_newsletter: false})

      refute Repo.get!(User, user.id).marketing_accepted
      assert_newsletter_settings(user, false)

      drain_events()
      assert_received {:mailjet_unsubscribe, :marketing_newsletter, "consent@example.com"}
    end

    test "writing an unchanged value does not touch Mailjet", %{user: user} do
      assert {:ok, _} =
               UserSettings.update_settings(user, %{is_subscribed_weekly_newsletter: false})

      drain_events()
      refute_received {:mailjet_unsubscribe, _, _}
      assert [] = ListConsent.history(user.id, :newsletter)
    end

    test "other settings in the same update are saved", %{user: user} do
      assert {:ok, %{settings: settings}} =
               UserSettings.update_settings(user, %{
                 is_subscribed_weekly_newsletter: true,
                 theme: "nightmode"
               })

      assert settings.is_subscribed_weekly_newsletter
      assert settings.theme == "nightmode"
    end

    test "the updateUserSettings mutation syncs the consent", %{conn: conn, user: user} do
      mutation = """
      mutation {
        updateUserSettings(settings: { isSubscribedWeeklyNewsletter: true }) {
          isSubscribedWeeklyNewsletter
          isSubscribedMarketingEmails
        }
      }
      """

      result =
        conn
        |> setup_jwt_auth(user)
        |> post("/graphql", mutation_skeleton(mutation))
        |> json_response(200)

      assert %{"isSubscribedWeeklyNewsletter" => true, "isSubscribedMarketingEmails" => true} =
               result["data"]["updateUserSettings"]

      assert Repo.get!(User, user.id).marketing_accepted

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
        assert_newsletter_settings(user, false)

        assert [_, %ListConsent{subscribed: false, source: :mailjet_unsubscribe}] =
                 ListConsent.history(user.id, :newsletter)

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

  describe "registration" do
    test "a new user is added to the welcome series but not to the old newsletter list", %{
      user: user
    } do
      Sanbase.Accounts.EventEmitter.emit_event({:ok, user}, :register_user, %{
        login_origin: :email
      })

      drain_events()
      assert_received {:mailjet_subscribe, :new_registrations, "consent@example.com"}
      refute_received {:mailjet_subscribe, :monthly_newsletter, _}
    end
  end

  describe "newsletter signup from a website form" do
    test "the subscription is applied when the email is verified", %{conn: conn, user: user} do
      {:ok, user} = User.Email.update_email_token(user, nil, true)

      assert Repo.get!(User, user.id).newsletter_opt_in_pending
      refute Repo.get!(User, user.id).marketing_accepted

      verify_email_login(conn, user)

      user = Repo.get!(User, user.id)
      assert user.marketing_accepted
      refute user.newsletter_opt_in_pending
      assert_newsletter_settings(user, true)

      assert [%ListConsent{subscribed: true, source: :website_form}] =
               ListConsent.history(user.id, :newsletter)

      drain_events()
      assert_received {:mailjet_subscribe, :marketing_newsletter, "consent@example.com"}
    end

    test "an unticked checkbox in the signup dialog right after does not undo it", %{
      conn: conn
    } do
      user = insert(:user, email: "digest@example.com", privacy_policy_accepted: false)
      {:ok, user} = User.Email.update_email_token(user, nil, true)
      verify_email_login(conn, user)

      {:ok, user} =
        Accounts.update_terms_and_conditions(Repo.get!(User, user.id), %{
          privacy_policy_accepted: true,
          marketing_accepted: false
        })

      assert user.privacy_policy_accepted
      assert user.marketing_accepted
      assert_newsletter_settings(user, true)

      drain_events()
      refute_received {:mailjet_unsubscribe, _, _}
    end

    test "a later login request without the signup clears it", %{conn: conn, user: user} do
      {:ok, _} = User.Email.update_email_token(user, nil, true)
      {:ok, user} = User.Email.update_email_token(user, nil, false)

      verify_email_login(conn, user)

      refute Repo.get!(User, user.id).marketing_accepted

      drain_events()
      refute_received {:mailjet_subscribe, :marketing_newsletter, _}
    end

    test "a normal login does not subscribe", %{conn: conn, user: user} do
      {:ok, user} = User.Email.update_email_token(user)

      verify_email_login(conn, user)

      refute Repo.get!(User, user.id).marketing_accepted
      assert [] = ListConsent.history(user.id, :newsletter)
    end
  end

  defp verify_email_login(conn, user) do
    mutation = """
    mutation {
      emailLoginVerify(email: "#{user.email}", token: "#{user.email_token}") {
        accessToken
      }
    }
    """

    result =
      conn
      |> post("/graphql", mutation_skeleton(mutation))
      |> json_response(200)

    assert result["data"]["emailLoginVerify"]["accessToken"]
  end

  defp assert_newsletter_settings(user, value) do
    settings = UserSettings.settings_for(user, force: true)
    assert settings.is_subscribed_weekly_newsletter == value
    assert settings.is_subscribed_marketing_emails == value
  end

  defp drain_events() do
    Sanbase.EventBus.drain_topics(@subscriber.topics(), 10_000)
  end
end
