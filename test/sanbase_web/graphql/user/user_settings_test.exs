defmodule SanbaseWeb.Graphql.UserSettingsTest do
  use SanbaseWeb.ConnCase, async: false

  alias Sanbase.Accounts.UserSettings

  import SanbaseWeb.Graphql.TestHelpers
  import Sanbase.Factory

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

  test "favorite metrics support random non existing metrics", %{user: user, conn: conn} do
    favorites = ["price_eth", "nvt", "non-existing-metric"]

    query = change_favorite_metrics_query(favorites)
    result = conn |> execute(query, "updateUserSettings")

    assert result["favoriteMetrics"] == ["price_eth", "nvt", "non-existing-metric"]

    assert UserSettings.settings_for(user, force: true) |> Map.get(:favorite_metrics) == [
             "price_eth",
             "nvt",
             "non-existing-metric"
           ]
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
             "isBetaMode" => true,
             "pageSize" => 100,
             "tableColumns" => %{"shown" => ["price", "volume"]},
             "theme" => "nightmode",
             "favorite_metrics" => ["daily_active_addresses", "nvt"],
             "isSubscribedBiweeklyReport" => false,
             "isSubscribedEduEmails" => true,
             "isSubscribedMonthlyNewsletter" => true,
             "isSubscribedMarketingEmails" => false
           }
  end

  test "returns default values if user has no user_settings", %{conn: conn} do
    query = current_user_query()
    result = conn |> execute(query, "currentUser")

    assert result["settings"] == %{
             "alertNotifyEmail" => false,
             "alertNotifyTelegram" => false,
             "isBetaMode" => false,
             "pageSize" => 20,
             "tableColumns" => %{},
             "theme" => "default",
             "favorite_metrics" => [],
             "isSubscribedBiweeklyReport" => false,
             "isSubscribedEduEmails" => true,
             "isSubscribedMonthlyNewsletter" => true,
             "isSubscribedMarketingEmails" => false
           }
  end

  describe "email settings" do
    test "get default email settings", context do
      result = execute_query(context.conn, current_user_query(), "currentUser")

      assert result["settings"]["isSubscribedEduEmails"]
      assert result["settings"]["isSubscribedMonthlyNewsletter"]
      refute result["settings"]["isSubscribedBiweeklyReport"]
    end

    test "update email settings", context do
      query = change_email_settings("isSubscribedMonthlyNewsletter: false")
      result = execute_mutation(context.conn, query)
      refute result["isSubscribedMonthlyNewsletter"]
    end

    test "only pro user can update bi-weekly report email setting", context do
      query = change_email_settings("isSubscribedBiweeklyReport: true")

      assert execute_mutation_with_error(context.conn, query) =~
               "Only PRO users can subscribe to Biweekly Report"

      insert(:subscription_pro_sanbase, user: context.user)
      query = change_email_settings("isSubscribedBiweeklyReport: true")
      result = execute_mutation(context.conn, query)
      assert result["isSubscribedBiweeklyReport"]
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
          isBetaMode
          theme
          pageSize
          tableColumns
          favorite_metrics
          isSubscribedEduEmails
          isSubscribedMonthlyNewsletter
          isSubscribedBiweeklyReport
          isSubscribedMarketingEmails
        }
      }
    }
    """
  end

  defp change_favorite_metrics_query(favorite_metrics) do
    """
    mutation {
      updateUserSettings(settings: #{map_to_input_object_str(%{favorite_metrics: favorite_metrics})})
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

  defp change_email_settings(arg) do
    """
    mutation {
      updateUserSettings(settings: {#{arg}}) {
        isSubscribedEduEmails
        isSubscribedMonthlyNewsletter
        isSubscribedBiweeklyReport
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

  defp execute(conn, query, query_str) do
    conn
    |> post("/graphql", mutation_skeleton(query))
    |> json_response(200)
    |> get_in(["data", query_str])
  end
end
