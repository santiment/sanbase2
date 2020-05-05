defmodule SanbaseWeb.Graphql.UserSettingsTest do
  use SanbaseWeb.ConnCase, async: false

  alias Sanbase.Auth.UserSettings

  import SanbaseWeb.Graphql.TestHelpers
  import Sanbase.Factory
  import Sanbase.TestHelpers

  setup_all_with_mocks([
    {Sanbase.Email.Mailchimp, [:passthrough], [unsubscribe_email: fn _ -> :ok end]},
    {Sanbase.Email.Mailchimp, [:passthrough], [subscribe_email: fn _ -> :ok end]}
  ]) do
    []
  end

  setup do
    user = insert(:user, email: "test@example.com")
    conn = setup_jwt_auth(build_conn(), user)

    {:ok, conn: conn, user: user}
  end

  test "toggle beta mode", %{user: user, conn: conn} do
    query = toggle_beta_mode_query(true)
    result = conn |> execute(query, "updateUserSettings")

    assert result == %{"isBetaMode" => true}
    assert UserSettings.settings_for(user) |> Map.get(:is_beta_mode) == true

    query = toggle_beta_mode_query(false)
    result = conn |> execute(query, "updateUserSettings")

    assert result == %{"isBetaMode" => false}
    assert UserSettings.settings_for(user) |> Map.get(:is_beta_mode) == false
  end

  test "change theme", %{user: user, conn: conn} do
    query = change_theme_query("nightmode")
    result = conn |> execute(query, "updateUserSettings")

    assert result == %{"theme" => "nightmode"}
    assert UserSettings.settings_for(user) |> Map.get(:theme) == "nightmode"

    query = change_theme_query("default")
    result = conn |> execute(query, "updateUserSettings")

    assert result == %{"theme" => "default"}
    assert UserSettings.settings_for(user) |> Map.get(:theme) == "default"
  end

  test "change page size", %{user: user, conn: conn} do
    query = change_page_size_query(100)
    result = conn |> execute(query, "updateUserSettings")

    assert result == %{"pageSize" => 100}
    assert UserSettings.settings_for(user) |> Map.get(:page_size) == 100

    query = change_page_size_query(50)
    result = conn |> execute(query, "updateUserSettings")

    assert result == %{"pageSize" => 50}
    assert UserSettings.settings_for(user) |> Map.get(:page_size) == 50
  end

  test "change table columns", %{user: user, conn: conn} do
    query = change_table_columns_query(%{shown: ["price", "volume", "devActivity"]})
    result = conn |> execute(query, "updateUserSettings")

    assert result == %{"tableColumns" => %{"shown" => ["price", "volume", "devActivity"]}}

    assert UserSettings.settings_for(user) |> Map.get(:table_columns) == %{
             "shown" => ["price", "volume", "devActivity"]
           }

    query = change_table_columns_query(%{shown: ["price"]})
    result = conn |> execute(query, "updateUserSettings")

    assert result == %{"tableColumns" => %{"shown" => ["price"]}}

    assert UserSettings.settings_for(user) |> Map.get(:table_columns) == %{"shown" => ["price"]}
  end

  test "toggle telegram notification channel", %{user: user, conn: conn} do
    query = toggle_telegram_channel_query(true)
    result = conn |> execute(query, "settingsToggleChannel")

    assert result == %{"signalNotifyTelegram" => true}
    assert UserSettings.settings_for(user) |> Map.get(:signal_notify_telegram) == true

    query = toggle_telegram_channel_query(false)
    result = conn |> execute(query, "settingsToggleChannel")

    assert result == %{"signalNotifyTelegram" => false}
    assert UserSettings.settings_for(user) |> Map.get(:signal_notify_telegram) == false
  end

  test "toggle email notification channel", %{user: user, conn: conn} do
    query = toggle_email_channel_query(true)
    result = conn |> execute(query, "settingsToggleChannel")

    assert result == %{"signalNotifyEmail" => true}
    assert UserSettings.settings_for(user) |> Map.get(:signal_notify_email) == true

    query = toggle_email_channel_query(false)
    result = conn |> execute(query, "settingsToggleChannel")

    assert result == %{"signalNotifyEmail" => false}
    assert UserSettings.settings_for(user) |> Map.get(:signal_notify_email) == false
  end

  test "toggle on existing record", %{user: user, conn: conn} do
    insert(:user_settings, user: user, settings: %{signal_notify_telegram: false})

    query = toggle_telegram_channel_query(true)
    result = conn |> execute(query, "settingsToggleChannel")

    assert result == %{"signalNotifyTelegram" => true}
    assert UserSettings.settings_for(user) |> Map.get(:signal_notify_telegram) == true
  end

  test "fetches settings for current user", %{user: user, conn: conn} do
    insert(:user_settings,
      user: user,
      settings: %{
        signal_notify_telegram: true,
        signal_notify_email: false,
        is_beta_mode: true,
        theme: "nightmode",
        page_size: 100,
        table_columns: %{shown: ["price", "volume"]}
      }
    )

    query = current_user_query()
    result = conn |> execute(query, "currentUser")

    assert result["settings"] == %{
             "signalNotifyEmail" => false,
             "signalNotifyTelegram" => true,
             "newsletterSubscription" => "OFF",
             "isBetaMode" => true,
             "pageSize" => 100,
             "tableColumns" => %{"shown" => ["price", "volume"]},
             "theme" => "nightmode"
           }
  end

  test "returns default values if user has'nt any user_settings", %{conn: conn} do
    query = current_user_query()
    result = conn |> execute(query, "currentUser")

    assert result["settings"] == %{
             "newsletterSubscription" => "OFF",
             "signalNotifyEmail" => false,
             "signalNotifyTelegram" => false,
             "isBetaMode" => false,
             "pageSize" => 20,
             "tableColumns" => %{},
             "theme" => "default"
           }
  end

  describe "newsletter subscription" do
    test "changes subscription to daily", %{conn: conn, user: user} do
      insert(:user_settings, user: user, settings: %{newsletter_subscription: "WEEKLY"})
      query = change_newsletter_subscription_query("DAILY")
      result = conn |> execute(query, "changeNewsletterSubscription")

      assert result["newsletterSubscription"] == "DAILY"
      assert UserSettings.settings_for(user) |> Map.get(:newsletter_subscription) == :daily
    end

    test "changes subscription to weekly", %{conn: conn, user: user} do
      insert(:user_settings, user: user, settings: %{newsletter_subscription: "DAILY"})
      query = change_newsletter_subscription_query("WEEKLY")
      result = conn |> execute(query, "changeNewsletterSubscription")

      assert result["newsletterSubscription"] == "WEEKLY"
      assert UserSettings.settings_for(user) |> Map.get(:newsletter_subscription) == :weekly
    end

    test "can turn off subscription", %{conn: conn, user: user} do
      insert(:user_settings, user: user, settings: %{newsletter_subscription: "WEEKLY"})
      query = change_newsletter_subscription_query("OFF")
      result = conn |> execute(query, "changeNewsletterSubscription")

      assert result["newsletterSubscription"] == "OFF"
      assert UserSettings.settings_for(user) |> Map.get(:newsletter_subscription) == :off
    end

    test "can handle unknown subscription types", %{conn: conn, user: user} do
      insert(:user_settings, user: user, settings: %{newsletter_subscription: "WEEKLY"})
      query = change_newsletter_subscription_query("UNKNOWN")
      result = conn |> execute(query, "changeNewsletterSubscription")

      assert result["newsletterSubscription"] == nil
      assert UserSettings.settings_for(user) |> Map.get(:newsletter_subscription) == :weekly
    end
  end

  defp current_user_query() do
    """
    {
      currentUser {
        id
        settings {
          signalNotifyEmail
          signalNotifyTelegram
          newsletterSubscription
          isBetaMode
          theme
          pageSize
          tableColumns
        }
      }
    }
    """
  end

  defp toggle_telegram_channel_query(is_active?) do
    """
    mutation {
      settingsToggleChannel(signalNotifyTelegram: #{is_active?}) {
        signalNotifyTelegram
      }
    }
    """
  end

  defp toggle_beta_mode_query(is_active?) do
    """
    mutation {
      updateUserSettings(settings: {isBetaMode: #{is_active?}}) {
        isBetaMode
      }
    }
    """
  end

  defp change_theme_query(theme) do
    """
    mutation {
      updateUserSettings(settings: {theme: "#{theme}"}) {
        theme
      }
    }
    """
  end

  defp change_table_columns_query(table_columns) do
    ~s|
    mutation {
      updateUserSettings(
        settings: {tableColumns: '#{table_columns |> Jason.encode!()}'}
        ) {
         tableColumns
      }
    }
    |
    |> String.replace(~r|\"|, ~S|\\"|)
    |> String.replace(~r|'|, ~S|"|)
  end

  defp change_page_size_query(page_size) do
    """
    mutation {
      updateUserSettings(settings: {pageSize: #{page_size}}) {
        pageSize
      }
    }
    """
  end

  defp toggle_email_channel_query(is_active?) do
    """
    mutation {
      settingsToggleChannel(signalNotifyEmail: #{is_active?}) {
        signalNotifyEmail
      }
    }
    """
  end

  defp change_newsletter_subscription_query(type) do
    """
    mutation {
      changeNewsletterSubscription(newsletterSubscription: #{type}) {
        newsletterSubscription
      }
    }
    """
  end

  defp execute(conn, query, query_str) do
    conn
    |> post("/graphql", mutation_skeleton(query))
    |> json_response(200)
    |> get_in(["data", query_str])
  end
end
