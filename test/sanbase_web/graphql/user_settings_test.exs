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
    query = fn is_active ->
      """
      mutation {
        settingsToggleChannel(signal_notify_telegram: #{is_active}) {
          signalNotifyTelegram
        }
      }
      """
    end

    result = conn |> post("/graphql", mutation_skeleton(query.(true)))

    assert json_response(result, 200)["data"]["settingsToggleChannel"] == %{
             "signalNotifyTelegram" => true
           }

    assert UserSettings.settings_for(user) |> Map.get(:signal_notify_telegram) == true

    result = conn |> post("/graphql", mutation_skeleton(query.(false)))

    assert json_response(result, 200)["data"]["settingsToggleChannel"] == %{
             "signalNotifyTelegram" => false
           }

    assert UserSettings.settings_for(user) |> Map.get(:signal_notify_telegram) == false
  end

  test "toggle email notification channel", %{user: user, conn: conn} do
    query = fn is_active ->
      """
      mutation {
        settingsToggleChannel(signal_notify_email: #{is_active}) {
          signalNotifyEmail
        }
      }
      """
    end

    result = conn |> post("/graphql", mutation_skeleton(query.(true)))

    assert json_response(result, 200)["data"]["settingsToggleChannel"] == %{
             "signalNotifyEmail" => true
           }

    assert UserSettings.settings_for(user) |> Map.get(:signal_notify_email) == true

    result = conn |> post("/graphql", mutation_skeleton(query.(false)))

    assert json_response(result, 200)["data"]["settingsToggleChannel"] == %{
             "signalNotifyEmail" => false
           }

    assert UserSettings.settings_for(user) |> Map.get(:signal_notify_email) == false
  end

  test "toggle on existing record", %{user: user, conn: conn} do
    insert(:user_settings, user: user, settings: %{signal_notify_telegram: false})

    query = """
    mutation {
      settingsToggleChannel(signal_notify_telegram: true) {
        signalNotifyTelegram
      }
    }
    """

    result = conn |> post("/graphql", mutation_skeleton(query))

    assert json_response(result, 200)["data"]["settingsToggleChannel"] == %{
             "signalNotifyTelegram" => true
           }

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

    query = """
    {
      currentUser {
        id,
        settings {
          signalNotifyEmail
          signalNotifyTelegram
        }
      }
    }
    """

    result =
      conn
      |> post("/graphql", query_skeleton(query, "currentUser"))

    assert json_response(result, 200)["data"]["currentUser"]["settings"] == %{
             "signalNotifyEmail" => false,
             "signalNotifyTelegram" => true
           }
  end

  test "returns empty settings if user hasn't any", %{conn: conn} do
    query = """
    {
      currentUser {
        id,
        settings {
          signalNotifyEmail
          signalNotifyTelegram
        }
      }
    }
    """

    result =
      conn
      |> post("/graphql", query_skeleton(query, "currentUser"))

    assert json_response(result, 200)["data"]["currentUser"]["settings"] == nil
  end
end
