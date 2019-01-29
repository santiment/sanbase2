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

  test "create trigger", %{user: user, conn: conn} do
    trigger = %{
      "type" => "daily_active_addresses",
      "target" => "santiment",
      "channel" => "telegram",
      "time_window" => "1d",
      "percent_threshold" => 300.0,
      "repeating" => false
    }

    trigger_json = trigger |> Jason.encode!()

    query =
      ~s|
    mutation {
      createTrigger(
        trigger: '#{trigger_json}'
      ) {
        id
        trigger
      }
    }
    |
      |> format_interpolated_json()

    result =
      conn
      |> post("/graphql", %{"query" => query})

    result = json_response(result, 200)["data"]["createTrigger"]
    created_trigger = result |> hd()

    assert created_trigger |> Map.get("trigger") == trigger
    assert created_trigger |> Map.get("id") != nil
  end

  test "update trigger", %{user: user, conn: conn} do
    trigger = %{
      "type" => "daily_active_addresses",
      "target" => "santiment",
      "channel" => "telegram",
      "time_window" => "1d",
      "percent_threshold" => 300.0,
      "repeating" => false
    }

    insert(:user_triggers, user: user, triggers: [%{is_public: false, trigger: trigger}])

    updated_trigger = trigger |> Map.put("percent_threshold", 400.0)
    trigger_id = UserTrigger.triggers_for(user) |> hd |> Map.get(:id)

    trigger_json = updated_trigger |> Jason.encode!()

    query =
      ~s|
    mutation {
      updateTrigger(
        id: '#{trigger_id}'
        trigger: '#{trigger_json}'
      ) {
        id
        trigger
      }
    }
    |
      |> format_interpolated_json()

    result =
      conn
      |> post("/graphql", %{"query" => query})

    result = json_response(result, 200)["data"]["updateTrigger"]
    result = result |> hd()

    assert result |> Map.get("trigger") == updated_trigger
    assert result |> Map.get("id") == trigger_id
  end

  test "get trigger by id", %{user: user, conn: conn} do
    trigger = %{
      "type" => "daily_active_addresses",
      "target" => "santiment",
      "channel" => "telegram",
      "time_window" => "1d",
      "percent_threshold" => 300.0,
      "repeating" => false
    }

    insert(:user_triggers, user: user, triggers: [%{is_public: false, trigger: trigger}])

    trigger_id = UserTrigger.triggers_for(user) |> hd |> Map.get(:id)

    query = """
    query {
      getTriggerById(
        id: "#{trigger_id}"
      ) {
        id
        trigger
      }
    }
    """

    result =
      conn
      |> post("/graphql", %{"query" => query})

    result = json_response(result, 200)["data"]["getTriggerById"]

    assert result |> Map.get("trigger") == trigger
    assert result |> Map.get("id") == trigger_id
  end

  test "fetches triggers for current user", %{user: user, conn: conn} do
    trigger = %{
      "type" => "daily_active_addresses",
      "target" => "santiment",
      "channel" => "telegram",
      "time_window" => "1d",
      "percent_threshold" => 300.0,
      "repeating" => false
    }

    insert(:user_triggers, user: user, triggers: [%{is_public: false, trigger: trigger}])

    query = """
    {
      currentUser {
        id,
        triggers {
          id
          trigger
        }
      }
    }
    """

    result =
      conn
      |> post("/graphql", query_skeleton(query, "currentUser"))

    result = json_response(result, 200)["data"]["currentUser"]["triggers"] |> hd()

    assert result |> Map.get("trigger") == trigger
    assert result |> Map.get("id") != nil
  end

  defp format_interpolated_json(string) do
    string
    |> String.replace(~r|\"|, ~S|\\"|)
    |> String.replace(~r|'|, ~S|"|)
  end
end
