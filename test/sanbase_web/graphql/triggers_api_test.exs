defmodule SanbaseWeb.Graphql.TriggersApiTest do
  use SanbaseWeb.ConnCase, async: false

  import Mock
  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  alias Sanbase.Signals.UserTrigger

  setup do
    user = insert(:user, email: "test@example.com")
    conn = setup_jwt_auth(build_conn(), user)

    {:ok, conn: conn, user: user}
  end

  test "create trigger", %{conn: conn} do
    with_mock Sanbase.Telegram,
      send_message: fn _user, text ->
        send(self(), {:telegram_to_self, text})
        :ok
      end do
      trigger_settings = default_trigger_settings()

      trigger_settings_json = trigger_settings |> Jason.encode!()

      query =
        ~s|
    mutation {
      createTrigger(
        settings: '#{trigger_settings_json}'
        title: 'Generic title'
        cooldown: '23h'
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

      # Telegram notification is sent when creation sucessful
      assert_receive(
        {:telegram_to_self, "Successfully created a new signal of type: Daily Active Addresses"}
      )

      created_trigger = json_response(result, 200)["data"]["createTrigger"]["trigger"]

      assert created_trigger["settings"] == trigger_settings
      assert created_trigger["id"] != nil
    end
  end

  test "create trigger with unknown type", %{conn: conn} do
    trigger_settings = %{
      "type" => "unknown",
      "target" => "santiment",
      "channel" => "telegram",
      "time_window" => "1d",
      "percent_threshold" => 300.0,
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

    # Telegram notification is not sent when creation is unsucessful
    refute_receive(
      {:telegram_to_self, "Successfully created a new signal of type: Daily Active Addresses"}
    )

    result =
      conn
      |> post("/graphql", %{"query" => query})
      |> json_response(200)

    error = result["errors"] |> List.first()

    assert error["message"] == "Trigger structure is invalid"
  end

  test "update trigger", %{user: user, conn: conn} do
    trigger_settings = default_trigger_settings()

    insert(:user_triggers, user: user, trigger: %{is_public: false, settings: trigger_settings})

    updated_trigger = trigger_settings |> Map.put("percent_threshold", 400.0)
    user_trigger = UserTrigger.triggers_for(user) |> List.first()
    trigger_id = user_trigger.id

    trigger_settings_json = updated_trigger |> Jason.encode!()

    query =
      ~s|
    mutation {
      updateTrigger(
        id: #{trigger_id}
        settings: '#{trigger_settings_json}'
        tags: ['tag1', 'tag2']
        cooldown: '23h'
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
    assert trigger["tags"] == [%{"name" => "tag1"}, %{"name" => "tag2"}]
  end

  test "remove trigger", %{user: user, conn: conn} do
    trigger_settings = default_trigger_settings()

    insert(:user_triggers, user: user, trigger: %{is_public: false, settings: trigger_settings})

    user_trigger = UserTrigger.triggers_for(user) |> List.first()
    trigger_id = user_trigger.id

    query =
      ~s|
    mutation {
      removeTrigger(
        id: #{trigger_id}
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
    trigger_settings = default_trigger_settings()

    insert(:user_triggers,
      user: user,
      trigger: %{is_public: false, settings: trigger_settings, title: "Some generic title"}
    )

    user_trigger = UserTrigger.triggers_for(user) |> List.first()
    trigger_id = user_trigger.id

    query = """
    query {
      getTriggerById(
        id: #{trigger_id}
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
    trigger_settings = default_trigger_settings()

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
    trigger_settings = default_trigger_settings()

    trigger_settings2 = Map.put(trigger_settings, "percent_threshold", 400.0)

    insert(:user_triggers, user: user, trigger: %{is_public: true, settings: trigger_settings})
    insert(:user_triggers, user: user, trigger: %{is_public: false, settings: trigger_settings2})

    query = """
    {
      allPublicTriggers {
        user_id
        trigger {
          id
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

    trigger_settings = default_trigger_settings()

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
    assert created_trigger["tags"] == [%{"name" => "SAN"}, %{"name" => "santiment"}]
  end

  test "fetches signals historical activity for current user", %{user: user, conn: conn} do
    trigger_settings = default_trigger_settings()

    user_trigger =
      insert(:user_triggers,
        user: user,
        trigger: %{
          is_public: false,
          settings: trigger_settings,
          title: "alabala",
          description: "portokala"
        }
      )

    _oldest =
      insert(:signals_historical_activity,
        user: user,
        user_trigger: user_trigger,
        payload: %{"all" => "oldest"},
        triggered_at: NaiveDateTime.from_iso8601!("2019-01-20T00:00:00")
      )

    first_activity =
      insert(:signals_historical_activity,
        user: user,
        user_trigger: user_trigger,
        payload: %{"all" => "first"},
        triggered_at: NaiveDateTime.from_iso8601!("2019-01-21T00:00:00")
      )

    second_activity =
      insert(:signals_historical_activity,
        user: user,
        user_trigger: user_trigger,
        payload: %{"all" => "second"},
        triggered_at: NaiveDateTime.from_iso8601!("2019-01-22T00:00:00")
      )

    # fetch the last 2 signal activities
    latest_two = current_user_signals_activity(conn, "limit: 2")

    assert NaiveDateTime.compare(
             NaiveDateTime.from_iso8601!(latest_two["cursor"]["before"]),
             first_activity.triggered_at
           ) == :eq

    assert NaiveDateTime.compare(
             NaiveDateTime.from_iso8601!(latest_two["cursor"]["after"]),
             second_activity.triggered_at
           ) == :eq

    assert latest_two["activity"]
           |> Enum.map(&Map.get(&1, "payload")) == [%{"all" => "second"}, %{"all" => "first"}]

    before_cursor = latest_two["cursor"]["before"]

    # fetch one activity before previous last 2 fetched activities
    before_cursor_res =
      current_user_signals_activity(
        conn,
        "limit: 1, cursor: {type: BEFORE, datetime: '#{before_cursor}'}"
      )

    assert before_cursor_res["activity"]
           |> Enum.map(&Map.get(&1, "payload")) == [%{"all" => "oldest"}]

    # insert new latest activity and fetch it with after cursor
    _latest =
      insert(:signals_historical_activity,
        user: user,
        user_trigger: user_trigger,
        payload: %{"all" => "latest"},
        triggered_at: NaiveDateTime.from_iso8601!("2019-01-23T00:00:00")
      )

    after_cursor = latest_two["cursor"]["after"]

    after_cursor_res =
      current_user_signals_activity(
        conn,
        "limit: 1, cursor: {type: AFTER, datetime: '#{after_cursor}'}"
      )

    assert after_cursor_res["activity"]
           |> Enum.map(&Map.get(&1, "payload")) == [%{"all" => "latest"}]
  end

  test "test fetching signal historical activities when there is none", %{conn: conn} do
    result = current_user_signals_activity(conn, "limit: 2")
    assert result["activity"] == []
    assert result["cursor"] == %{"after" => nil, "before" => nil}

    result =
      current_user_signals_activity(
        conn,
        "limit: 1, cursor: {type: BEFORE, datetime: '2019-01-20T00:00:00Z'}"
      )

    assert result["activity"] == []
    assert result["cursor"] == %{"after" => nil, "before" => nil}

    result =
      current_user_signals_activity(
        conn,
        "limit: 1, cursor: {type: AFTER, datetime: '2019-01-20T00:00:00Z'}"
      )

    assert result["activity"] == []
    assert result["cursor"] == %{"after" => nil, "before" => nil}
  end

  test "fetch signal historical activities without logged in user" do
    assert current_user_signals_activity(
             build_conn(),
             "limit: 1"
           ) == nil
  end

  test "deactivate signal", %{user: user, conn: conn} do
    trigger_settings = default_trigger_settings()

    ut = insert(:user_triggers, user: user, trigger: %{settings: trigger_settings})

    assert ut.trigger.active

    updated_trigger = update_active_query(conn, ut.id, false)

    assert updated_trigger["active"] == false
  end

  test "activate signal", %{user: user, conn: conn} do
    trigger_settings = default_trigger_settings()

    ut = insert(:user_triggers, user: user, trigger: %{active: false, settings: trigger_settings})

    refute ut.trigger.active

    updated_trigger = update_active_query(conn, ut.id, true)

    assert updated_trigger["active"] == true
  end

  defp current_user_signals_activity(conn, args_str) do
    query =
      ~s|
    {
      signalsHistoricalActivity(#{args_str}) {
        cursor {
          after
          before
        }
        activity {
          payload,
          triggered_at,
          userTrigger {
            trigger {
              title,
              description
            }
          }
        }
      }
    }|
      |> format_interpolated_json()

    result =
      conn
      |> post("/graphql", query_skeleton(query, "signalsHistoricalActivity"))
      |> json_response(200)

    result["data"]["signalsHistoricalActivity"]
  end

  defp update_active_query(conn, id, active) do
    query = """
      mutation {
        updateTrigger(
          id: #{id},
          active: #{active}
        ) {
          trigger{
            active
          }
        }
      }
    """

    result =
      conn
      |> post("/graphql", %{"query" => query})
      |> json_response(200)

    result["data"]["updateTrigger"]["trigger"]
  end

  defp default_trigger_settings do
    %{
      "type" => "daily_active_addresses",
      "target" => "santiment",
      "channel" => "telegram",
      "time_window" => "1d",
      "percent_threshold" => 300.0
    }
  end

  defp format_interpolated_json(string) do
    string
    |> String.replace(~r|\"|, ~S|\\"|)
    |> String.replace(~r|'|, ~S|"|)
  end
end
