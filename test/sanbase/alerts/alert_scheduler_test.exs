defmodule Sanbase.Alert.SchedulerTest do
  use Sanbase.DataCase, async: false

  import Sanbase.Factory
  import ExUnit.CaptureLog

  alias Sanbase.Alert.{UserTrigger, HistoricalActivity}
  alias Sanbase.Alert.Trigger.MetricTriggerSettings

  setup do
    Sanbase.Cache.clear_all(:alerts_evaluator_cache)

    Tesla.Mock.mock_global(fn %{method: :post} -> %Tesla.Env{status: 200, body: "ok"} end)

    project = insert(:random_erc20_project)

    user = insert(:user, user_settings: %{settings: %{alert_notify_telegram: true}})

    Sanbase.Accounts.UserSettings.set_telegram_chat_id(user.id, 123_123_123_123)

    trigger_settings = %{
      type: "metric_signal",
      metric: "active_addresses_24h",
      target: %{slug: project.slug},
      channel: "telegram",
      operation: %{above: 300}
    }

    {:ok, trigger} =
      UserTrigger.create_user_trigger(user, %{
        title: "Generic title",
        is_public: true,
        cooldown: "12h",
        settings: trigger_settings
      })

    mock_fun =
      [
        fn -> {:ok, %{project.slug => 100}} end,
        fn -> {:ok, %{project.slug => 5000}} end
      ]
      |> Sanbase.Mock.wrap_consecutives(arity: 5)

    [
      trigger: trigger,
      project: project,
      price_usd: 62,
      user: user,
      mock_fun: mock_fun
    ]
  end

  test "frozen triggers do not get scheduled", context do
    %{user: user, trigger: trigger} = context

    UserTrigger.update_user_trigger(user.id, %{
      id: trigger.id,
      is_frozen: true
    })

    ut = Sanbase.Repo.get(UserTrigger, trigger.id)
    assert ut.trigger.is_frozen == true

    log =
      capture_log(fn ->
        Sanbase.Alert.Scheduler.run_alert(MetricTriggerSettings)
      end)

    assert log =~
             "In total 1/1 active receivable alerts of type metric_signal are frozen and won't be processed."

    assert log =~ "In total 0 alerts will be processed"
  end

  test "active is_repeating: false triggers again", context do
    %{user: user, trigger: trigger, project: project} = context

    UserTrigger.update_user_trigger(user.id, %{
      id: trigger.id,
      cooldown: "0s",
      is_repeating: false
    })

    Sanbase.Mock.prepare_mock2(
      &Sanbase.Clickhouse.MetricAdapter.aggregated_timeseries_data/5,
      {:ok, %{project.slug => 5000}}
    )
    |> Sanbase.Mock.run_with_mocks(fn ->
      ut = Sanbase.Repo.get(UserTrigger, trigger.id)
      assert ut.trigger.is_repeating == false
      assert ut.trigger.is_active == true

      assert capture_log(fn ->
               Sanbase.Alert.Scheduler.run_alert(MetricTriggerSettings)
             end) =~
               "In total 1/1 metric_signal alerts were sent successfully"

      ut = Sanbase.Repo.get(UserTrigger, trigger.id)
      assert ut.trigger.is_repeating == false
      assert ut.trigger.is_active == false

      # Once triggered because of is_repeating: false, is_active
      # has been changed to false
      UserTrigger.update_user_trigger(user.id, %{
        id: trigger.id,
        is_active: true
      })

      ut = Sanbase.Repo.get(UserTrigger, trigger.id)
      assert ut.trigger.is_repeating == false
      assert ut.trigger.is_active == true

      assert capture_log(fn ->
               Sanbase.Alert.Scheduler.run_alert(MetricTriggerSettings)
             end) =~
               "In total 1/1 metric_signal alerts were sent successfully"

      ut = Sanbase.Repo.get(UserTrigger, trigger.id)
      assert ut.trigger.is_repeating == false
      assert ut.trigger.is_active == false
    end)
  end

  test "successful signal is written in signals_historical_activity", context do
    %{mock_fun: mock_fun, user: user, project: project} = context

    Sanbase.Mock.prepare_mock(
      Sanbase.Clickhouse.MetricAdapter,
      :aggregated_timeseries_data,
      mock_fun
    )
    |> Sanbase.Mock.run_with_mocks(fn ->
      Sanbase.Alert.Scheduler.run_alert(MetricTriggerSettings)

      activity = HistoricalActivity |> Sanbase.Repo.all() |> List.first()

      assert activity.user_id == user.id

      # Test payload
      [{identifier, payload}] = Enum.take(activity.payload, 1)
      assert identifier == project.slug
      assert String.contains?(payload, "is above 300")
      assert String.contains?(payload, project.name)

      # Test data (kv list)
      [{identifier, kv}] = Enum.take(activity.data["user_trigger_data"], 1)
      assert identifier == project.slug
      assert is_map(kv)
      assert kv["type"] == MetricTriggerSettings.type()
      assert kv["value"] == 5000
    end)
  end

  test "successful signal is written in timeline_events", context do
    %{
      mock_fun: mock_fun,
      user: user,
      trigger: trigger,
      project: project
    } = context

    Sanbase.Mock.prepare_mock(
      Sanbase.Clickhouse.MetricAdapter,
      :aggregated_timeseries_data,
      mock_fun
    )
    |> Sanbase.Mock.run_with_mocks(fn ->
      Sanbase.Alert.Scheduler.run_alert(MetricTriggerSettings)

      Process.sleep(100)

      Sanbase.Timeline.TimelineEvent |> Sanbase.Repo.all()

      [_create_trigger_event, fired_trigger_event] =
        Sanbase.Timeline.TimelineEvent
        |> Sanbase.Repo.all()

      assert fired_trigger_event.id != nil
      assert fired_trigger_event.event_type == "trigger_fired"
      assert fired_trigger_event.user_id == user.id
      assert fired_trigger_event.user_trigger_id == trigger.id

      # Test payload
      [{identifier, payload}] = Enum.take(fired_trigger_event.payload, 1)
      assert identifier == project.slug
      assert String.contains?(payload, "is above 300")
      assert String.contains?(payload, project.name)

      # Test data (kv list)
      [{identifier, kv}] = Enum.take(fired_trigger_event.data["user_trigger_data"], 1)
      assert identifier == project.slug
      assert is_map(kv)
      assert kv["type"] == MetricTriggerSettings.type()
      assert kv["value"] == 5000
    end)
  end

  test "email channel for user without email", context do
    %{mock_fun: mock_fun, project: project} = context

    user_no_email = insert(:user, email: nil)

    trigger_settings = %{
      type: "metric_signal",
      metric: "active_addresses_24h",
      target: %{slug: project.slug},
      channel: "email",
      operation: %{above: 300}
    }

    {:ok, trigger} =
      UserTrigger.create_user_trigger(user_no_email, %{
        title: "Generic title",
        is_public: true,
        cooldown: "12h",
        settings: trigger_settings
      })

    Sanbase.Mock.prepare_mock(
      Sanbase.Clickhouse.MetricAdapter,
      :aggregated_timeseries_data,
      mock_fun
    )
    |> Sanbase.Mock.run_with_mocks(fn ->
      log =
        capture_log(fn ->
          Sanbase.Alert.Scheduler.run_alert(MetricTriggerSettings)
        end)

      # 1/2 because there is one alert with telegram channel created in the setup
      assert log =~
               "In total 1/2 active alerts of type metric_signal are not being computed because they cannot be sent"

      assert log =~
               "The owners of these alerts have disabled the notification channels or has no telegram/email linked to their account"

      ut = Sanbase.Repo.get(UserTrigger, trigger.id)

      # Previously "error" was put as the identifier instead the project's slug
      # In case of email/telegram sending fails the last_triggered still needs
      # to be updated properly as next run will trigger the signal again and
      # appear multiple times in user's feed
      assert Map.get(ut.trigger.last_triggered, "error") == nil

      assert Map.get(ut.trigger.last_triggered, project.slug) == nil
    end)
  end
end
