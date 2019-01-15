defmodule SanbaseWeb.Graphql.UserSettingsTest do
  use SanbaseWeb.ConnCase, async: false

  alias Sanbase.Auth.UserSettings

  import SanbaseWeb.Graphql.TestHelpers
  import Sanbase.Factory

  setup do
    user = insert(:user)
    conn = setup_jwt_auth(build_conn(), user)

    {:ok, conn: conn, user: user}
  end

  test "toggle telegram notification channel", %{user: user, conn: conn} do
    query = """
    mutation {
      settingsToggleTelegramChannel
    }
    """

    result = conn |> post("/graphql", mutation_skeleton(query))
    assert json_response(result, 200)["data"]["settingsToggleTelegramChannel"] == true
    assert UserSettings.settings_for(user) |> Map.get(:signal_notify_telegram) == true

    result = conn |> post("/graphql", mutation_skeleton(query))
    assert json_response(result, 200)["data"]["settingsToggleTelegramChannel"] == false
    assert UserSettings.settings_for(user) |> Map.get(:signal_notify_telegram) == false
  end

  test "toggle email notification channel", %{user: user, conn: conn} do
    query = """
    mutation {
      settingsToggleEmailChannel
    }
    """

    result = conn |> post("/graphql", mutation_skeleton(query))

    assert json_response(result, 200)["data"]["settingsToggleEmailChannel"] == true
    assert UserSettings.settings_for(user) |> Map.get(:signal_notify_email) == true

    result = conn |> post("/graphql", mutation_skeleton(query))

    assert json_response(result, 200)["data"]["settingsToggleEmailChannel"] == false
    assert UserSettings.settings_for(user) |> Map.get(:signal_notify_email) == false
  end

  test "toggle on existing record", %{user: user, conn: conn} do
    insert(:user_settings, user: user, signal_notify_telegram: false)

    query = """
    mutation {
      settingsToggleTelegramChannel
    }
    """

    result = conn |> post("/graphql", mutation_skeleton(query))

    assert json_response(result, 200)["data"]["settingsToggleTelegramChannel"] == true
    assert UserSettings.settings_for(user) |> Map.get(:signal_notify_telegram) == true
  end

  test "generate telegram url when telegram active", %{user: user, conn: conn} do
    test_url = "https://example.com"
    insert(:user_settings, user: user, signal_notify_telegram: true)

    query = """
    mutation {
      settingsGenerateTelegramUrl
    }
    """

    result = conn |> post("/graphql", mutation_skeleton(query))

    assert json_response(result, 200)["data"]["settingsGenerateTelegramUrl"] == test_url
    assert UserSettings.settings_for(user) |> Map.get(:telegram_url) == test_url
  end

  test "generate telegram url when telegram not active", %{user: user, conn: conn} do
    insert(:user_settings, user: user, signal_notify_telegram: false)

    query = """
    mutation {
      settingsGenerateTelegramUrl
    }
    """

    result = conn |> post("/graphql", mutation_skeleton(query))
    [error] = json_response(result, 200)["errors"]

    assert json_response(result, 200)["data"]["settingsGenerateTelegramUrl"] == nil
    assert String.contains?(error["message"], "Telegram channel is not active!")
    assert UserSettings.settings_for(user) |> Map.get(:telegram_url) == nil
  end
end
