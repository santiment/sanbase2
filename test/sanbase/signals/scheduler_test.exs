defmodule Sanbase.Signal.SchedulerTest do
  use Sanbase.DataCase, async: false

  import Sanbase.Factory
  import Sanbase.TestHelpers

  alias Sanbase.Signal.{UserTrigger, HistoricalActivity}
  alias Sanbase.Signal.Trigger.MetricTriggerSettings

  setup do
    Sanbase.Signal.Evaluator.Cache.clear()

    Tesla.Mock.mock_global(fn %{method: :post} -> %Tesla.Env{status: 200, body: "ok"} end)

    project = insert(:random_erc20_project)
    user = insert(:user)
    Sanbase.Auth.UserSettings.set_telegram_chat_id(user.id, 123_123_123_123)

    trigger_settings = %{
      type: "metric_signal",
      metric: Sanbase.Metric.available_metrics() |> hd(),
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

    datetimes = generate_datetimes(~U[2019-01-01 00:00:00Z], "1d", 7)

    mock_fun =
      [
        fn -> {:ok, [%{datetime: datetimes |> List.first(), value: 100}]} end,
        fn -> {:ok, [%{datetiem: datetimes |> List.last(), value: 5000}]} end
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

  test "successfull signal is written in signals_historical_activity", context do
    %{mock_fun: mock_fun, user: user, project: project} = context

    Sanbase.Mock.prepare_mock(Sanbase.Metric, :timeseries_data, mock_fun)
    |> Sanbase.Mock.run_with_mocks(fn ->
      Sanbase.Signal.Scheduler.run_signal(MetricTriggerSettings)

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

  test "successfull signal is written in timeline_events", context do
    %{
      mock_fun: mock_fun,
      user: user,
      trigger: trigger,
      project: project
    } = context

    Sanbase.Mock.prepare_mock(Sanbase.Metric, :timeseries_data, mock_fun)
    |> Sanbase.Mock.run_with_mocks(fn ->
      Sanbase.Signal.Scheduler.run_signal(MetricTriggerSettings)

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
      metric: Sanbase.Metric.available_metrics() |> hd(),
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

    Sanbase.Mock.prepare_mock(Sanbase.Metric, :timeseries_data, mock_fun)
    |> Sanbase.Mock.run_with_mocks(fn ->
      Sanbase.Signal.Scheduler.run_signal(MetricTriggerSettings)
      ut = Sanbase.Repo.get(UserTrigger, trigger.id)

      # Previously "error" was put as the identifier instead the project's slug
      # In case of email/telegram sending fails the last_triggered still needs
      # to be updated properly as next run will trigger the signal again and
      # appear multiple times in user's feed
      assert Map.get(ut.trigger.last_triggered, "error") == nil

      assert %DateTime{} =
               Map.get(ut.trigger.last_triggered, project.slug)
               |> Sanbase.DateTimeUtils.from_iso8601!()
    end)
  end
end
