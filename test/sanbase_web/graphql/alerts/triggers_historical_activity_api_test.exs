defmodule SanbaseWeb.Graphql.TriggersHistoricalActivityApiTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  setup do
    user = insert(:user)
    conn = setup_jwt_auth(build_conn(), user)

    {:ok, conn: conn, user: user}
  end

  test "alerts historical activity from sanclan user", %{conn: conn} do
    san_clan_user = insert(:user)
    role_san_family = insert(:role_san_family)
    insert(:user_role, user: san_clan_user, role: role_san_family)

    trigger_settings = default_trigger_settings_string_keys()

    user_trigger1 =
      insert(:user_trigger,
        user: san_clan_user,
        trigger: %{
          is_public: true,
          settings: trigger_settings,
          title: "alabala",
          description: "portokala"
        }
      )

    user_trigger2 =
      insert(:user_trigger,
        user: san_clan_user,
        trigger: %{
          is_public: false,
          settings: trigger_settings,
          title: "alabala",
          description: "portokala"
        }
      )

    insert(:alerts_historical_activity,
      user: san_clan_user,
      user_trigger: user_trigger1,
      payload: %{"all" => "first"},
      triggered_at: NaiveDateTime.from_iso8601!("2019-01-21T00:00:00")
    )

    insert(:alerts_historical_activity,
      user: san_clan_user,
      user_trigger: user_trigger2,
      payload: %{"all" => "second"},
      triggered_at: NaiveDateTime.from_iso8601!("2019-01-21T00:00:00")
    )

    latest_two = current_user_alerts_activity(conn, "limit: 2")

    assert latest_two["activity"]
           |> Enum.map(&Map.get(&1, "payload")) == [%{"all" => "first"}]
  end

  test "fetches alerts historical activity for current user", %{user: user, conn: conn} do
    trigger_settings = default_trigger_settings_string_keys()

    user_trigger =
      insert(:user_trigger,
        user: user,
        trigger: %{
          is_public: false,
          settings: trigger_settings,
          title: "alabala",
          description: "portokala"
        }
      )

    _oldest =
      insert(:alerts_historical_activity,
        user: user,
        user_trigger: user_trigger,
        payload: %{"all" => "oldest"},
        triggered_at: NaiveDateTime.from_iso8601!("2019-01-20T00:00:00")
      )

    first_activity =
      insert(:alerts_historical_activity,
        user: user,
        user_trigger: user_trigger,
        payload: %{"all" => "first"},
        triggered_at: NaiveDateTime.from_iso8601!("2019-01-21T00:00:00")
      )

    second_activity =
      insert(:alerts_historical_activity,
        user: user,
        user_trigger: user_trigger,
        payload: %{"all" => "second"},
        triggered_at: NaiveDateTime.from_iso8601!("2019-01-22T00:00:00")
      )

    # fetch the last 2 signal activities
    latest_two = current_user_alerts_activity(conn, "limit: 2")

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
      current_user_alerts_activity(
        conn,
        "limit: 1, cursor: {type: BEFORE, datetime: '#{before_cursor}'}"
      )

    assert before_cursor_res["activity"]
           |> Enum.map(&Map.get(&1, "payload")) == [%{"all" => "oldest"}]

    # insert new latest activity and fetch it with after cursor
    _latest =
      insert(:alerts_historical_activity,
        user: user,
        user_trigger: user_trigger,
        payload: %{"all" => "latest"},
        triggered_at: NaiveDateTime.from_iso8601!("2019-01-23T00:00:00")
      )

    after_cursor = latest_two["cursor"]["after"]

    after_cursor_res =
      current_user_alerts_activity(
        conn,
        "limit: 1, cursor: {type: AFTER, datetime: '#{after_cursor}'}"
      )

    assert after_cursor_res["activity"]
           |> Enum.map(&Map.get(&1, "payload")) == [%{"all" => "latest"}]
  end

  test "test fetching signal historical activities when there is none", %{conn: conn} do
    result = current_user_alerts_activity(conn, "limit: 2")
    assert result["activity"] == []
    assert result["cursor"] == %{"after" => nil, "before" => nil}

    result =
      current_user_alerts_activity(
        conn,
        "limit: 1, cursor: {type: BEFORE, datetime: '2019-01-20T00:00:00Z'}"
      )

    assert result["activity"] == []
    assert result["cursor"] == %{"after" => nil, "before" => nil}

    result =
      current_user_alerts_activity(
        conn,
        "limit: 1, cursor: {type: AFTER, datetime: '2019-01-20T00:00:00Z'}"
      )

    assert result["activity"] == []
    assert result["cursor"] == %{"after" => nil, "before" => nil}
  end

  test "fetch signal historical activities without logged in user" do
    assert current_user_alerts_activity(
             build_conn(),
             "limit: 1"
           ) == nil
  end

  defp current_user_alerts_activity(conn, args_str) do
    query =
      ~s|
    {
      alertsHistoricalActivity(#{args_str}) {
        cursor {
          after
          before
        }
        activity {
          payload
          data
          triggered_at
          trigger {
            id
            title
            description
          }
        }
      }
    }|
      |> format_interpolated_json()

    result =
      conn
      |> post("/graphql", query_skeleton(query, "alertsHistoricalActivity"))
      |> json_response(200)

    result["data"]["alertsHistoricalActivity"]
  end

  defp default_trigger_settings_string_keys() do
    %{
      "type" => "daily_active_addresses",
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
