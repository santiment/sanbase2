defmodule SanbaseWeb.Graphql.UserSettingsTest do
  use SanbaseWeb.ConnCase, async: false

  alias Sanbase.Accounts.UserSettings

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

  test "change favorite metrics", %{user: user, conn: conn} do
    favorites = ["price_eth", "nvt", "mvrv_usd"]

    query = change_favorite_metrics_query(favorites)
    result = conn |> execute(query, "updateUserSettings")

    assert result == %{"favoriteMetrics" => favorites}

    assert UserSettings.settings_for(user, force: true) |> Map.get(:favorite_metrics) == favorites

    favorites = ["price_btc", "nvt", "mvrv_usd"]

    query = change_favorite_metrics_query(favorites)
    result = conn |> execute(query, "updateUserSettings")

    assert result == %{"favoriteMetrics" => favorites}

    assert UserSettings.settings_for(user, force: true) |> Map.get(:favorite_metrics) == favorites
  end

  test "change favorite metrics with invalid value", %{user: user, conn: conn} do
    favorites = ["price_eth", "nvt", "asdfqwerty"]

    query = change_favorite_metrics_query(favorites)
    result = conn |> execute(query, "updateUserSettings")

    assert result["favoriteMetrics"] == nil

    assert UserSettings.settings_for(user, force: true) |> Map.get(:favorite_metrics) == []
  end

  test "toggle beta mode", %{user: user, conn: conn} do
    query = toggle_beta_mode_query(true)
    result = conn |> execute(query, "updateUserSettings")

    assert result == %{"isBetaMode" => true}
    assert UserSettings.settings_for(user, force: true) |> Map.get(:is_beta_mode) == true

    query = toggle_beta_mode_query(false)
    result = conn |> execute(query, "updateUserSettings")

    assert result == %{"isBetaMode" => false}
    assert UserSettings.settings_for(user, force: true) |> Map.get(:is_beta_mode) == false
  end

  test "change theme", %{user: user, conn: conn} do
    query = change_theme_query("nightmode")
    result = conn |> execute(query, "updateUserSettings")

    assert result == %{"theme" => "nightmode"}
    assert UserSettings.settings_for(user, force: true) |> Map.get(:theme) == "nightmode"

    query = change_theme_query("default")
    result = conn |> execute(query, "updateUserSettings")

    assert result == %{"theme" => "default"}
    assert UserSettings.settings_for(user, force: true) |> Map.get(:theme) == "default"
  end

  test "change page size", %{user: user, conn: conn} do
    query = change_page_size_query(100)
    result = conn |> execute(query, "updateUserSettings")

    assert result == %{"pageSize" => 100}
    assert UserSettings.settings_for(user, force: true) |> Map.get(:page_size) == 100

    query = change_page_size_query(50)
    result = conn |> execute(query, "updateUserSettings")

    assert result == %{"pageSize" => 50}
    assert UserSettings.settings_for(user, force: true) |> Map.get(:page_size) == 50
  end

  test "change table columns", %{user: user, conn: conn} do
    query = change_table_columns_query(%{shown: ["price", "volume", "devActivity"]})
    result = conn |> execute(query, "updateUserSettings")

    assert result == %{"tableColumns" => %{"shown" => ["price", "volume", "devActivity"]}}

    assert UserSettings.settings_for(user, force: true) |> Map.get(:table_columns) == %{
             "shown" => ["price", "volume", "devActivity"]
           }

    query = change_table_columns_query(%{shown: ["price"]})
    result = conn |> execute(query, "updateUserSettings")

    assert result == %{"tableColumns" => %{"shown" => ["price"]}}

    assert UserSettings.settings_for(user, force: true) |> Map.get(:table_columns) == %{
             "shown" => ["price"]
           }
  end

  test "toggle telegram notification channel", %{user: user, conn: conn} do
    query = toggle_telegram_channel_query(true)
    result = conn |> execute(query, "settingsToggleChannel")

    assert result == %{"alertNotifyTelegram" => true}

    assert UserSettings.settings_for(user, force: true) |> Map.get(:alert_notify_telegram) ==
             true

    query = toggle_telegram_channel_query(false)
    result = conn |> execute(query, "settingsToggleChannel")

    assert result == %{"alertNotifyTelegram" => false}

    assert UserSettings.settings_for(user, force: true) |> Map.get(:alert_notify_telegram) ==
             false
  end

  test "toggle email notification channel", %{user: user, conn: conn} do
    query = toggle_email_channel_query(true)
    result = conn |> execute(query, "settingsToggleChannel")

    assert result == %{"alertNotifyEmail" => true}
    assert UserSettings.settings_for(user, force: true) |> Map.get(:alert_notify_email) == true

    query = toggle_email_channel_query(false)
    result = conn |> execute(query, "settingsToggleChannel")

    assert result == %{"alertNotifyEmail" => false}
    assert UserSettings.settings_for(user, force: true) |> Map.get(:alert_notify_email) == false
  end

  test "toggle on existing record", %{user: user, conn: conn} do
    insert(:user_settings, user: user, settings: %{alert_notify_telegram: false})

    query = toggle_telegram_channel_query(true)
    result = conn |> execute(query, "settingsToggleChannel")

    assert result == %{"alertNotifyTelegram" => true}

    assert UserSettings.settings_for(user, force: true) |> Map.get(:alert_notify_telegram) ==
             true
  end

  test "fetches settings for current user", %{user: user, conn: conn} do
    insert(:user_settings,
      user: user,
      settings: %{
        alert_notify_telegram: true,
        alert_notify_email: false,
        is_beta_mode: true,
        theme: "nightmode",
        page_size: 100,
        table_columns: %{shown: ["price", "volume"]},
        favorite_metrics: ["daily_active_addresses", "nvt"]
      }
    )

    query = current_user_query()
    result = conn |> execute(query, "currentUser")

    assert result["settings"] == %{
             "alertNotifyEmail" => false,
             "alertNotifyTelegram" => true,
             "newsletterSubscription" => "OFF",
             "isBetaMode" => true,
             "pageSize" => 100,
             "tableColumns" => %{"shown" => ["price", "volume"]},
             "theme" => "nightmode",
             "favorite_metrics" => ["daily_active_addresses", "nvt"]
           }
  end

  test "returns default values if user has no user_settings", %{conn: conn} do
    query = current_user_query()
    result = conn |> execute(query, "currentUser")

    assert result["settings"] == %{
             "newsletterSubscription" => "OFF",
             "alertNotifyEmail" => false,
             "alertNotifyTelegram" => false,
             "isBetaMode" => false,
             "pageSize" => 20,
             "tableColumns" => %{},
             "theme" => "default",
             "favorite_metrics" => []
           }
  end

  describe "newsletter subscription" do
    test "changes subscription to daily", %{conn: conn, user: user} do
      insert(:user_settings, user: user, settings: %{newsletter_subscription: "WEEKLY"})
      query = change_newsletter_subscription_query("DAILY")
      result = conn |> execute(query, "changeNewsletterSubscription")

      assert result["newsletterSubscription"] == "DAILY"

      assert UserSettings.settings_for(user, force: true) |> Map.get(:newsletter_subscription) ==
               :daily
    end

    test "changes subscription to weekly", %{conn: conn, user: user} do
      insert(:user_settings, user: user, settings: %{newsletter_subscription: "DAILY"})
      query = change_newsletter_subscription_query("WEEKLY")
      result = conn |> execute(query, "changeNewsletterSubscription")

      assert result["newsletterSubscription"] == "WEEKLY"

      assert UserSettings.settings_for(user, force: true) |> Map.get(:newsletter_subscription) ==
               :weekly
    end

    test "can turn off subscription", %{conn: conn, user: user} do
      insert(:user_settings, user: user, settings: %{newsletter_subscription: "WEEKLY"})
      query = change_newsletter_subscription_query("OFF")
      result = conn |> execute(query, "changeNewsletterSubscription")

      assert result["newsletterSubscription"] == "OFF"

      assert UserSettings.settings_for(user, force: true) |> Map.get(:newsletter_subscription) ==
               :off
    end

    test "can handle unknown subscription types", %{conn: conn, user: user} do
      insert(:user_settings, user: user, settings: %{newsletter_subscription: "WEEKLY"})
      query = change_newsletter_subscription_query("UNKNOWN")
      result = conn |> execute(query, "changeNewsletterSubscription")

      assert result["newsletterSubscription"] == nil

      assert UserSettings.settings_for(user, force: true) |> Map.get(:newsletter_subscription) ==
               :weekly
    end
  end

  defp current_user_query() do
    """
    {
      currentUser {
        id
        settings {
          alertNotifyEmail
          alertNotifyTelegram
          newsletterSubscription
          isBetaMode
          theme
          pageSize
          tableColumns
          favorite_metrics
        }
      }
    }
    """
  end

  defp change_favorite_metrics_query(favorite_metrics) do
    """
    mutation {
      updateUserSettings(settings: #{
      map_to_input_object_str(%{favorite_metrics: favorite_metrics})
    })
      {
        favoriteMetrics
      }
    }
    """
  end

  defp toggle_telegram_channel_query(is_active?) do
    """
    mutation {
      settingsToggleChannel(alertNotifyTelegram: #{is_active?}) {
        alertNotifyTelegram
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
      settingsToggleChannel(alertNotifyEmail: #{is_active?}) {
        alertNotifyEmail
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
