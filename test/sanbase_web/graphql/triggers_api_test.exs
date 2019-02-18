defmodule SanbaseWeb.Graphql.TriggersApiTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory

  import SanbaseWeb.Graphql.TestHelpers

  alias Sanbase.Signals.UserTrigger

  setup do
    user = insert(:user, email: "test@example.com")
    conn = setup_jwt_auth(build_conn(), user)

    {:ok, conn: conn, user: user}
  end

  test "create trigger", %{conn: conn} do
    trigger_settings = %{
      "type" => "daily_active_addresses",
      "target" => "santiment",
      "channel" => "telegram",
      "time_window" => "1d",
      "percent_threshold" => 300.0,
      "repeating" => false,
      "payload" => nil,
      "triggered?" => false
    }

    trigger_settings_json = trigger_settings |> Jason.encode!()

    query =
      ~s|
    mutation {
      createTrigger(
        settings: '#{trigger_settings_json}'
        title: 'Generic title'
      ) {
        trigger{
          id
          settings
        }
      }
    }
    |
      |> format_interpolated_json()

    result =
      conn
      |> post("/graphql", %{"query" => query})

    created_trigger = json_response(result, 200)["data"]["createTrigger"]["trigger"]

    assert created_trigger |> Map.get("settings") == trigger_settings
    assert created_trigger |> Map.get("id") != nil
  end

  test "create trigger with unknown type", %{conn: conn} do
    trigger_settings = %{
      "type" => "unknown",
      "target" => "santiment",
      "channel" => "telegram",
      "time_window" => "1d",
      "percent_threshold" => 300.0,
      "repeating" => false,
      "payload" => nil,
      "triggered?" => false
    }

    trigger_settings_json = trigger_settings |> Jason.encode!()

    query =
      ~s|
    mutation {
      createTrigger(
        settings: '#{trigger_settings_json}'
        title: 'Generic title'
      ) {
        trigger{
          id
          settings
        }
      }
    }
    |
      |> format_interpolated_json()

    result =
      conn
      |> post("/graphql", %{"query" => query})

    [error] = json_response(result, 200)["errors"]

    assert error["message"] == "Trigger structure is invalid"
  end

  test "update trigger", %{user: user, conn: conn} do
    trigger_settings = %{
      "type" => "daily_active_addresses",
      "target" => "santiment",
      "channel" => "telegram",
      "time_window" => "1d",
      "percent_threshold" => 300.0,
      "repeating" => false,
      "payload" => nil,
      "triggered?" => false
    }

    insert(:user_triggers, user: user, trigger: %{is_public: false, settings: trigger_settings})

    updated_trigger = trigger_settings |> Map.put("percent_threshold", 400.0)
    trigger_id = UserTrigger.triggers_for(user) |> hd |> Map.get(:id)

    trigger_settings_json = updated_trigger |> Jason.encode!()

    query =
      ~s|
    mutation {
      updateTrigger(
        id: '#{trigger_id}'
        settings: '#{trigger_settings_json}'
      ) {
        trigger{
          id
          settings
        }
      }
    }
    |
      |> format_interpolated_json()

    result =
      conn
      |> post("/graphql", %{"query" => query})
      |> json_response(200)

    assert result["data"]["updateTrigger"]["trigger"] |> Map.get("settings") == updated_trigger
    assert result["data"]["updateTrigger"]["trigger"] |> Map.get("id") == trigger_id
  end

  test "get trigger by id", %{user: user, conn: conn} do
    trigger_settings = %{
      "type" => "daily_active_addresses",
      "target" => "santiment",
      "filtered_target_list" => [],
      "channel" => "telegram",
      "time_window" => "1d",
      "percent_threshold" => 300.0,
      "repeating" => false,
      "payload" => nil,
      "triggered?" => false
    }

    insert(:user_triggers, user: user, trigger: %{is_public: false, settings: trigger_settings})

    trigger_id = UserTrigger.triggers_for(user) |> hd |> Map.get(:id)

    query = """
    query {
      getTriggerById(
        id: "#{trigger_id}"
      ) {
        trigger{
          id
          settings
        }
      }
    }
    """

    result =
      conn
      |> post("/graphql", %{"query" => query})

    result = json_response(result, 200)["data"]["getTriggerById"]["trigger"]

    assert result |> Map.get("settings") == trigger_settings
    assert result |> Map.get("id") == trigger_id
  end

  test "fetches triggers for current user", %{user: user, conn: conn} do
    trigger_settings = %{
      "type" => "daily_active_addresses",
      "target" => "santiment",
      "filtered_target_list" => [],
      "channel" => "telegram",
      "time_window" => "1d",
      "percent_threshold" => 300.0,
      "repeating" => false,
      "payload" => nil,
      "triggered?" => false
    }

    insert(:user_triggers, user: user, trigger: %{is_public: false, settings: trigger_settings})

    query = """
    {
      currentUser {
        id,
        triggers {
          id
          settings
        }
      }
    }
    """

    result =
      conn
      |> post("/graphql", query_skeleton(query, "currentUser"))

    result = json_response(result, 200)["data"]["currentUser"]["triggers"] |> hd()

    assert result |> Map.get("settings") == trigger_settings
    assert result |> Map.get("id") != nil
  end

  test "fetches all public triggers", %{user: user, conn: conn} do
    trigger_settings = %{
      "type" => "daily_active_addresses",
      "target" => "santiment",
      "filtered_target_list" => [],
      "channel" => "telegram",
      "time_window" => "1d",
      "percent_threshold" => 300.0,
      "repeating" => false,
      "payload" => nil,
      "triggered?" => false
    }

    trigger_settings2 = Map.put(trigger_settings, "percent_threshold", 400.0)

    insert(:user_triggers, user: user, trigger: %{is_public: true, settings: trigger_settings})
    insert(:user_triggers, user: user, trigger: %{is_public: false, settings: trigger_settings2})

    query = """
    {
      allPublicTriggers {
        user_id
        trigger {
          id,
          settings
        }
      }
    }
    """

    result =
      conn
      |> post("/graphql", query_skeleton(query, "allPublicTriggers"))

    result = json_response(result, 200)["data"]["allPublicTriggers"]
    assert length(result) == 1
    assert result |> hd() |> Map.get("trigger") |> Map.get("settings") == trigger_settings
  end

  test "fetches public user triggers", %{conn: conn} do
    user = insert(:user, email: "alabala@example.com")

    trigger_settings = %{
      "type" => "daily_active_addresses",
      "target" => "santiment",
      "filtered_target_list" => [],
      "channel" => "telegram",
      "time_window" => "1d",
      "percent_threshold" => 300.0,
      "repeating" => false,
      "payload" => nil,
      "triggered?" => false
    }

    trigger_settings2 = Map.put(trigger_settings, "percent_threshold", 400.0)

    insert(:user_triggers, user: user, trigger: %{is_public: true, settings: trigger_settings})
    insert(:user_triggers, user: user, trigger: %{is_public: false, settings: trigger_settings2})

    query = """
    {
      publicTriggersForUser(user_id: #{user.id}) {
        trigger{
          id
          settings
        }
      }
    }
    """

    result =
      conn
      |> post("/graphql", query_skeleton(query, "publicTriggersForUser"))
      |> json_response(200)

    result = result["data"]["publicTriggersForUser"]
    assert length(result) == 1
    assert result |> hd |> Map.get("trigger") |> Map.get("settings") == trigger_settings
  end

  test "create trending words trigger", %{conn: conn} do
    trigger_settings = %{
      "type" => "trending_words",
      "channel" => "telegram",
      "trigger_time" => "12:00:00"
    }

    trigger_settings_json = trigger_settings |> Jason.encode!()
    tags = ["santiment", "SAN"]

    query =
      ~s|
    mutation {
      createTrigger(
        settings: '#{trigger_settings_json}'
        title: 'Generic title'
        tags: ['SAN', 'santiment']
      ) {
        trigger{
          id
          settings
          tags{ name }
        }
      }
    }
    |
      |> format_interpolated_json()

    result =
      conn
      |> post("/graphql", %{"query" => query})
      |> json_response(200)

    created_trigger = result["data"]["createTrigger"]["trigger"]

    assert created_trigger |> Map.get("settings") == trigger_settings
    assert created_trigger |> Map.get("id") != nil
  end

  defp format_interpolated_json(string) do
    string
    |> String.replace(~r|\"|, ~S|\\"|)
    |> String.replace(~r|'|, ~S|"|)
  end
end
