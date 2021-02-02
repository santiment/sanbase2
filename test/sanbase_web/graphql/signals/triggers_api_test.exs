defmodule SanbaseWeb.Graphql.TriggersApiTest do
  use SanbaseWeb.ConnCase, async: false

  import Mock
  import Sanbase.Factory
  import ExUnit.CaptureLog
  import SanbaseWeb.Graphql.TestHelpers

  alias Sanbase.Alert.UserTrigger

  setup do
    user = insert(:user)
    conn = setup_jwt_auth(build_conn(), user)

    {:ok, conn: conn, user: user}
  end

  describe "Create traigger" do
    test "with proper args - creates it successfully", %{conn: conn} do
      with_mock Sanbase.Telegram,
        send_message: fn _user, text ->
          send(self(), {:telegram_to_self, text})
          :ok
        end do
        trigger_settings = default_trigger_settings_string_keys()

        result = create_trigger(conn, settings: trigger_settings, cooldown: "23h")
        created_trigger = result["data"]["createTrigger"]["trigger"]

        # Telegram notification is sent when creation sucessful
        assert_receive({:telegram_to_self, message})

        assert message =~
                 """
                 Successfully created a new alert of type: Metric Signal

                 Title: Generic title

                 This bot will send you a message when the alert triggers 🤖
                 """

        assert created_trigger["settings"] == trigger_settings
        assert created_trigger["id"] != nil
        assert created_trigger["cooldown"] == "23h"
        assert created_trigger["tags"] == []
      end
    end

    test "with unknown type - returns proper error", %{conn: conn} do
      trigger_settings = %{
        "type" => "unknown",
        "target" => "santiment",
        "channel" => "telegram",
        "time_window" => "1d",
        "payload" => nil,
        "triggered?" => false
      }

      # Telegram notification is not sent when creation is unsucessful
      refute_receive({:telegram_to_self, _msg})

      assert capture_log(fn ->
               result = create_trigger(conn, title: "Some title", settings: trigger_settings)

               error = result["errors"] |> List.first()

               assert error["message"] ==
                        "Trigger structure is invalid. Key `settings` is not valid. Reason: \"The trigger settings type 'unknown' is not a valid type.\""
             end) =~
               "UserTrigger struct is not valid. Reason: \"The trigger settings type 'unknown' is not a valid type"
    end

    test "with mistyped field in settings - returns proper error", %{conn: conn} do
      trigger_settings = %{
        "type" => "metric_signal",
        "metric" => "active_addresses_24h",
        "target" => %{"slug" => "santiment"},
        "channel" => "telegram",
        "time_window" => "1d",
        "operation" => %{"random_field_not_present" => 300}
      }

      capture_log(fn ->
        %{"errors" => [%{"message" => error_message}]} =
          create_trigger(conn, title: "Some title", settings: trigger_settings)

        assert error_message =~ "Trigger structure is invalid. Key `settings` is not valid."
      end) =~
        "Trigger structure is invalid."
    end
  end

  test "load trigger with mistyped settings", %{conn: conn} do
    trigger_settings = %{
      "type" => "metric_signal",
      "metric" => "active_addresses_24h",
      "target" => %{"slug" => "santiment"},
      "channel" => "telegram",
      "time_window" => "1d",
      "operation" => %{"percent_up" => 300}
    }

    result = create_trigger(conn, title: "Some title", settings: trigger_settings)
    id = result["data"]["createTrigger"]["trigger"]["id"]

    # Manually update the field to bypass the validations
    ut = Sanbase.Repo.get(UserTrigger, id)

    Ecto.Changeset.change(ut, %{
      trigger: %{settings: %{ut.trigger.settings | "operation" => %{"asdjasldjkasd" => 1209}}}
    })
    |> Sanbase.Repo.update()

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

    conn
    |> post("/graphql", query_skeleton(query, "currentUser"))
    |> json_response(200)
  end

  test "update trigger", %{user: user, conn: conn} do
    trigger_settings =
      default_trigger_settings_string_keys() |> Map.put("operation", %{"percent_up" => 400.0})

    user_trigger =
      insert(:user_trigger, user: user, trigger: %{is_public: false, settings: trigger_settings})

    trigger =
      update_trigger(conn, user_trigger.id, trigger_settings, ["tag1", "tag2"], "123h", false)
      |> get_in(["data", "updateTrigger", "trigger"])

    assert trigger["settings"] == trigger_settings
    assert trigger["id"] == user_trigger.id
    assert trigger["cooldown"] == "123h"
    assert trigger["isRepeating"] == false
    assert trigger["tags"] == [%{"name" => "tag1"}, %{"name" => "tag2"}]
  end

  test "remove trigger", %{user: user, conn: conn} do
    trigger_settings = default_trigger_settings_string_keys()

    insert(:user_trigger, user: user, trigger: %{is_public: false, settings: trigger_settings})

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
    trigger_settings = default_trigger_settings_string_keys()

    ut =
      insert(:user_trigger,
        user: user,
        trigger: %{is_public: false, settings: trigger_settings, title: "Some generic title"}
      )

    trigger_id = ut.id
    result = get_trigger_by_id(conn, trigger_id)

    trigger = result["data"]["getTriggerById"]["trigger"]

    assert trigger["settings"] == trigger_settings
    assert trigger["id"] == trigger_id
  end

  test "can get other user public trigger", %{conn: conn} do
    ut =
      insert(:user_trigger,
        user: insert(:user),
        trigger: %{
          is_public: true,
          settings: default_trigger_settings_string_keys(),
          title: "Some generic title"
        }
      )

    result = get_trigger_by_id(conn, ut.id)

    assert result["data"]["getTriggerById"]["trigger"]["id"] == ut.id
  end

  test "cannot get other user private trigger", %{conn: conn} do
    ut =
      insert(:user_trigger,
        user: insert(:user),
        trigger: %{
          is_public: false,
          settings: default_trigger_settings_string_keys(),
          title: "Some generic title"
        }
      )

    %{"errors" => [%{"message" => error_message}]} = get_trigger_by_id(conn, ut.id)

    assert error_message =~ "does not exist or it is a private trigger owned by another user"
  end

  test "fetches triggers for current user", %{user: user, conn: conn} do
    trigger_settings = default_trigger_settings_string_keys()

    %{id: id} =
      insert(:user_trigger, user: user, trigger: %{is_public: false, settings: trigger_settings})

    query = """
    {
      currentUser {
        id,
        triggers {
          id
          settings
          tags {name}
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
    assert trigger["id"] == id
    assert trigger["tags"] == []
  end

  test "fetches all public triggers", %{user: user, conn: conn} do
    trigger_settings = default_trigger_settings_string_keys()

    trigger_settings2 = Map.put(trigger_settings, "operation", %{"percent_up" => 400.0})

    insert(:user_trigger, user: user, trigger: %{is_public: true, settings: trigger_settings})
    insert(:user_trigger, user: user, trigger: %{is_public: false, settings: trigger_settings2})

    query = """
    {
      allPublicTriggers {
        user_id
        trigger {
          id
          settings
          tags {name}
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
    assert user_trigger["trigger"]["tags"] == []
  end

  test "fetches public user triggers", %{conn: conn} do
    user = insert(:user)

    trigger_settings = default_trigger_settings_string_keys()
    trigger_settings2 = Map.put(trigger_settings, "operation", %{"percent_up" => 400.0})

    insert(:user_trigger, user: user, trigger: %{is_public: true, settings: trigger_settings})
    insert(:user_trigger, user: user, trigger: %{is_public: false, settings: trigger_settings2})

    query = """
    {
      publicTriggersForUser(user_id: #{user.id}) {
        trigger{
          id
          settings
          tags {name}
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
    assert trigger["trigger"]["tags"] == []
  end

  test "create trending words trigger", %{conn: conn} do
    trigger_settings = %{
      "type" => "trending_words",
      "channel" => "telegram",
      "operation" => %{"send_at_predefined_time" => true, "trigger_time" => "12:00:00"}
    }

    result =
      create_trigger(conn,
        title: "Generic title",
        settings: trigger_settings,
        tags: ["SAN", "santiment"]
      )

    created_trigger = result["data"]["createTrigger"]["trigger"]

    assert created_trigger["settings"] == trigger_settings
    assert created_trigger["id"] != nil
    assert created_trigger["tags"] == [%{"name" => "SAN"}, %{"name" => "santiment"}]
  end

  defp update_trigger(conn, trigger_id, trigger_settings, tags, cooldown, is_repeating) do
    tags_str = tags |> Enum.map(&"'#{&1}'") |> Enum.join(", ")
    trigger_settings_json = trigger_settings |> Jason.encode!()

    query =
      ~s|
    mutation {
      updateTrigger(
        id: #{trigger_id}
        settings: '#{trigger_settings_json}'
        tags: [#{tags_str}]
        cooldown: '#{cooldown}'
        isRepeating: #{is_repeating}
      ) {
        trigger{
          id
          cooldown
          isRepeating
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
  end

  defp create_trigger(conn, opts) do
    settings_json = Keyword.get(opts, :settings) |> Jason.encode!()

    query =
      ~s|
    mutation {
      createTrigger(
        settings: '#{settings_json}'
        title: '#{Keyword.get(opts, :title, "Generic title")}'
        tags: [#{Keyword.get(opts, :tags, []) |> Enum.map(&"'#{&1}'") |> Enum.join(",")}]
        cooldown: '#{Keyword.get(opts, :cooldown, "24h")}'
      ) {
        trigger{
          id
          settings
          cooldown
          tags{ name }
        }
      }
    }
    |
      |> format_interpolated_json()

    conn
    |> post("/graphql", %{"query" => query})
    |> json_response(200)
  end

  defp get_trigger_by_id(conn, id) do
    query = """
    query {
      getTriggerById(
        id: #{id}
        ) {
          trigger{
            id
            settings
        }
      }
    }
    """

    conn
    |> post("/graphql", %{"query" => query})
    |> json_response(200)
  end

  defp default_trigger_settings_string_keys() do
    %{
      "type" => "metric_signal",
      "metric" => "active_addresses_24h",
      "target" => %{"slug" => "santiment"},
      "channel" => "telegram",
      "time_window" => "1d",
      "operation" => %{"percent_up" => 300.0}
    }
  end

  defp format_interpolated_json(string) do
    string
    |> String.replace(~r|\"|, ~S|\\"|)
    |> String.replace(~r|'|, ~S|"|)
  end
end
