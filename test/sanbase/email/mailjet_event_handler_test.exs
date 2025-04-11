defmodule Sanbase.Email.MailjetEventHandlerTest do
  use Sanbase.DataCase, async: false

  import Sanbase.Factory

  alias Sanbase.Email.MailjetEventHandler
  alias Sanbase.Accounts.{User, UserSettings}
  alias Sanbase.Repo

  describe "handle_unsubscribe/2" do
    setup do
      user = insert(:user, email: "test@example.com")

      insert(:user_settings,
        user: user,
        settings: %{
          is_subscribed_metric_updates: true,
          is_subscribed_monthly_newsletter: true,
          is_subscribed_marketing_emails: true,
          is_subscribed_biweekly_report: true
        }
      )

      %{user: user}
    end

    test "successfully unsubscribes user from metric updates", %{user: user} do
      assert {:ok, _} = MailjetEventHandler.handle_unsubscribe(user.email, "10327883")

      # Reload user settings
      updated_settings = UserSettings.settings_for(user)
      refute updated_settings.is_subscribed_metric_updates
      assert updated_settings.is_subscribed_monthly_newsletter
      assert updated_settings.is_subscribed_marketing_emails
      assert updated_settings.is_subscribed_biweekly_report
    end

    test "successfully unsubscribes user from monthly newsletter", %{user: user} do
      assert {:ok, _} = MailjetEventHandler.handle_unsubscribe(user.email, "61085")

      # Reload user settings
      updated_settings = UserSettings.settings_for(user)
      assert updated_settings.is_subscribed_metric_updates
      refute updated_settings.is_subscribed_monthly_newsletter
      assert updated_settings.is_subscribed_marketing_emails
      assert updated_settings.is_subscribed_biweekly_report
    end

    test "returns error for unknown list id" do
      assert {:error, :unknown_list_id} =
               MailjetEventHandler.handle_unsubscribe("test@example.com", "99999")
    end

    test "returns error for non-existent user" do
      assert {:error, :user_not_found} =
               MailjetEventHandler.handle_unsubscribe("nonexistent@example.com", "10327883")
    end
  end

  describe "get_setting_key_for_list/1" do
    test "returns correct setting key for valid list ids" do
      assert {:ok, :is_subscribed_metric_updates} =
               MailjetEventHandler.get_setting_key_for_list("10327883")

      assert {:ok, :is_subscribed_monthly_newsletter} =
               MailjetEventHandler.get_setting_key_for_list("61085")

      assert {:ok, :is_subscribed_marketing_emails} =
               MailjetEventHandler.get_setting_key_for_list("10321582")
    end

    test "returns error for unknown list id" do
      assert {:error, :unknown_list_id} = MailjetEventHandler.get_setting_key_for_list("99999")
    end
  end
end
