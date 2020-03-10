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

    mock_data =
      generate_datetimes(~U[2019-01-01 00:00:00Z], "1d", 7)
      |> Enum.zip([100, 100, 100, 100, 100, 100, 5000])
      |> Enum.map(&%{datetime: elem(&1, 0), value: elem(&1, 1)})

    [
      trigger: trigger,
      project: project,
      price_usd: 62,
      user: user,
      mock_data: mock_data,
      mock_chart: [%{image: %{url: "somelink"}}]
    ]
  end

  test "successfull signal is written in signals_historical_activity", context do
    %{mock_data: mock_data, mock_chart: mock_chart, user: user, project: project} = context

    Sanbase.Mock.prepare_mock2(&Sanbase.Metric.timeseries_data/5, {:ok, mock_data})
    |> Sanbase.Mock.prepare_mock2(&Sanbase.GoogleChart.build_embedded_chart/4, {:ok, mock_chart})
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
      mock_data: mock_data,
      mock_chart: mock_chart,
      user: user,
      trigger: trigger,
      project: project
    } = context

    Sanbase.Mock.prepare_mock2(&Sanbase.Metric.timeseries_data/5, {:ok, mock_data})
    |> Sanbase.Mock.prepare_mock2(&Sanbase.GoogleChart.build_embedded_chart/4, {:ok, mock_chart})
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
end
