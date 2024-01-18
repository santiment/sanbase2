defmodule SanbaseWeb.Graphql.Alerts.TriggersStatsTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  setup do
    user = insert(:user)
    conn = setup_jwt_auth(build_conn(), user)
    insert(:project, slug: "santiment")

    {:ok, conn: conn, user: user}
  end

  test "when no alerts, stats are empty", context do
    assert Sanbase.Alerts.Stats.fired_alerts_24h(context.user.id) == %{}
    assert alert_stats_error(context.conn) == "No stats available"
  end

  test "when no alerts today", context do
    create_user_trigger(context)
    |> create_alert_historical_activity(3)

    assert Sanbase.Alerts.Stats.fired_alerts_24h(context.user.id) == %{}
    assert alert_stats_error(context.conn) == "No stats available"
  end

  test "when weekly avg equals todays count", context do
    user_trigger = create_user_trigger(context)

    for _ <- 1..6 do
      create_alert_historical_activity(user_trigger, 3)
    end

    create_alert_historical_activity(user_trigger, 0)

    assert Sanbase.Alerts.Stats.fired_alerts_24h(context.user.id) == %{
             data: [
               %{
                 alert_types: ["Transaction volume"],
                 count: 1,
                 percent_change: +0.0,
                 slug: "santiment"
               }
             ],
             total_fired: 1,
             total_fired_percent_change: +0.0,
             total_fired_weekly_avg: 1.0
           }

    assert alert_stats(context.conn) == %{
             "data" => [
               %{
                 "project" => %{"slug" => "santiment"},
                 "alertTypes" => ["Transaction volume"],
                 "count" => 1,
                 "percentChange" => +0.0,
                 "slug" => "santiment"
               }
             ],
             "totalFired" => 1,
             "totalFiredPercentChange" => +0.0,
             "totalFiredWeeklyAvg" => 1.0
           }
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

  defp create_user_trigger(context) do
    insert(:user_trigger,
      user: context.user,
      trigger: %{
        is_public: false,
        settings: default_trigger_settings_string_keys(),
        title: "alabala",
        description: "portokala"
      }
    )
  end

  def create_alert_historical_activity(user_trigger, days) do
    insert(:alerts_historical_activity,
      user: user_trigger.user,
      user_trigger: user_trigger,
      payload: %{},
      data: %{
        "user_trigger_data" => %{
          "santiment" => %{"type" => "metric_signal", "metric" => "transaction_volume"}
        }
      },
      triggered_at: Timex.shift(Timex.now(), days: -days)
    )
  end

  defp alert_stats_query do
    """
    {
      alertsStats {
        totalFired
        totalFiredWeeklyAvg
        totalFiredPercentChange
        data {
          slug
          project { slug }
          count
          percentChange
          alertTypes
        }
      }
    }
    """
  end

  defp alert_stats(conn) do
    execute_query(conn, alert_stats_query(), "alertsStats")
  end

  defp alert_stats_error(conn) do
    execute_query_with_error(conn, alert_stats_query(), "alertsStats")
  end
end
