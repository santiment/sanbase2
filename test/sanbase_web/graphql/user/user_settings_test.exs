defmodule SanbaseWeb.Graphql.UserSettingsTest do
  use SanbaseWeb.ConnCase, async: false

  alias Sanbase.Auth.UserSettings

  import SanbaseWeb.Graphql.TestHelpers
  import Sanbase.Factory

  setup do
    user = insert(:user, email: "test@example.com")
    conn = setup_jwt_auth(build_conn(), user)

    {:ok, conn: conn, user: user}
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
        signal_notify_email: false
      }
    )

    query = current_user_query()
    result = conn |> execute(query, "currentUser")

    assert result["settings"] == %{
             "signalNotifyEmail" => false,
             "signalNotifyTelegram" => true,
             "subscribedToNewsletter" => false
           }
  end

  test "returns empty settings if user hasn't any", %{conn: conn} do
    query = current_user_query()
    result = conn |> execute(query, "currentUser")

    assert result["settings"] == nil
  end

  test "subscribe/unsibscribe newsletter", %{conn: conn, user: user} do
    query = toggle_newsletter_subscription_query(true)
    result = conn |> execute(query, "toggleNewsletterSubscription")

    assert result["subscribedToNewsletter"] == true
    assert UserSettings.settings_for(user) |> Map.get(:subscribed_to_newsletter) == true

    query = toggle_newsletter_subscription_query(false)
    result = conn |> execute(query, "toggleNewsletterSubscription")

    assert result["subscribedToNewsletter"] == false
    assert UserSettings.settings_for(user) |> Map.get(:subscribed_to_newsletter) == false
  end

  defp current_user_query() do
    """
    {
      currentUser {
        id,
        settings {
          signalNotifyEmail
          signalNotifyTelegram
          subscribedToNewsletter
        }
      }
    }
    """
  end

  defp toggle_telegram_channel_query(is_active?) do
    """
    mutation {
      settingsToggleChannel(signalNotifyTelegram: #{is_active?}) {
        signalNotifyTelegram,
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

  defp toggle_newsletter_subscription_query(subscribe?) do
    """
    mutation {
      toggleNewsletterSubscription(subscribedToNewsletter: #{subscribe?}) {
        subscribedToNewsletter
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
