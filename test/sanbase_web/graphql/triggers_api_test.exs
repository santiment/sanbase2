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

    assert created_trigger["settings"] == trigger_settings
    assert created_trigger["id"] != nil
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
      |> json_response(200)

    error = result["errors"] |> List.first()

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
    user_trigger = UserTrigger.triggers_for(user) |> List.first()
    trigger_id = user_trigger.trigger.id

    trigger_settings_json = updated_trigger |> Jason.encode!()
    tags = [%{"name" => "tag1"}, %{"name" => "tag2"}]

    query =
      ~s|
    mutation {
      updateTrigger(
        id: '#{trigger_id}'
        settings: '#{trigger_settings_json}'
        tags: ['tag1', 'tag2']
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

    trigger = result["data"]["updateTrigger"]["trigger"]

    assert trigger["settings"] == updated_trigger
    assert trigger["id"] == trigger_id
    assert trigger["tags"] == tags
  end

  test "remove trigger", %{user: user, conn: conn} do
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

    user_trigger = UserTrigger.triggers_for(user) |> List.first()
    trigger_id = user_trigger.trigger.id

    query =
      ~s|
    mutation {
      removeTrigger(
        id: '#{trigger_id}'
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

    conn
    |> post("/graphql", %{"query" => query})
    |> json_response(200)

    assert UserTrigger.triggers_for(user) == []
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

    insert(:user_triggers,
      user: user,
      trigger: %{is_public: false, settings: trigger_settings, title: "Some generic title"}
    )

    user_trigger = UserTrigger.triggers_for(user) |> List.first()
    trigger_id = user_trigger.trigger.id

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
      |> json_response(200)

    trigger = result["data"]["getTriggerById"]["trigger"]

    assert trigger["settings"] == trigger_settings
    assert trigger["id"] == trigger_id
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
      |> json_response(200)

    trigger =
      result["data"]["currentUser"]["triggers"]
      |> hd()

    assert trigger["settings"] == trigger_settings
    assert trigger["id"] != nil
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
      |> json_response(200)

    triggers = result["data"]["allPublicTriggers"]
    assert length(triggers) == 1
    user_trigger = triggers |> List.first()
    assert user_trigger["trigger"]["settings"] == trigger_settings
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

    triggers = result["data"]["publicTriggersForUser"]
    assert length(triggers) == 1
    trigger = triggers |> List.first()
    assert trigger["trigger"]["settings"] == trigger_settings
  end

  test "create trending words trigger", %{conn: conn} do
    trigger_settings = %{
      "type" => "trending_words",
      "channel" => "telegram",
      "trigger_time" => "12:00:00"
    }

    trigger_settings_json = trigger_settings |> Jason.encode!()
    tags = [%{"name" => "SAN"}, %{"name" => "santiment"}]

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

    assert created_trigger["settings"] == trigger_settings
    assert created_trigger["id"] != nil
    assert created_trigger["tags"] == tags
  end

  defp format_interpolated_json(string) do
    string
    |> String.replace(~r|\"|, ~S|\\"|)
    |> String.replace(~r|'|, ~S|"|)
  end
end
