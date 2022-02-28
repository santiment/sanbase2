defmodule SanbaseWeb.Graphql.Alerts.TriggersStatsTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  setup do
    user = insert(:user)
    conn = setup_jwt_auth(build_conn(), user)

    {:ok, conn: conn, user: user}
  end

  test "1", context do
    trigger_settings = default_trigger_settings_string_keys()

    user_trigger =
      insert(:user_trigger,
        user: context.user,
        trigger: %{
          is_public: false,
          settings: trigger_settings,
          title: "alabala",
          description: "portokala"
        }
      )

    days_ago = fn days -> Timex.shift(Timex.now(), days: -days) end

    insert(:alerts_historical_activity,
      user: context.user,
      user_trigger: user_trigger,
      payload: %{},
      data: %{"user_trigger_data" => %{"santiment" => %{"type" => "metric_signal"}}},
      triggered_at: days_ago.(3)
    )

    insert(:alerts_historical_activity,
      user: context.user,
      user_trigger: user_trigger,
      payload: %{},
      data: %{"user_trigger_data" => %{"santiment" => %{"type" => "metric_signal"}}},
      triggered_at: Timex.now()
    )

    assert Sanbase.Alerts.Stats.fired_alerts_24h(context.user.id) == %{}
  end

  defp default_trigger_settings_string_keys() do
    %{
      "type" => "metric_signal",
      "metric" => "transaction_volume",
      "target" => %{"slug" => "santiment"},
      "channel" => "telegram",
      "time_window" => "1h",
      "operation" => %{"percent_up" => 300.0}
    }
  end
end
