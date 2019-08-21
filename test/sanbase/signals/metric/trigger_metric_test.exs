defmodule Sanbase.Signal.TriggerMetricTest do
  use Sanbase.DataCase, async: false

  import Mock
  import Sanbase.Factory
  import Sanbase.TestHelpers
  import ExUnit.CaptureLog

  alias Sanbase.Signal.UserTrigger
  alias Sanbase.Signal.Evaluator
  alias Sanbase.Clickhouse.Metric
  alias Sanbase.Signal.Trigger.MetricTriggerSettings

  setup_with_mocks([
    {Sanbase.Chart, [],
     [
       build_embedded_chart: fn _, _, _, _ -> [%{image: %{url: "somelink"}}] end,
       build_embedded_chart: fn _, _, _ -> [%{image: %{url: "somelink"}}] end
     ]},
    {
      Sanbase.Timeline.TimelineEvent,
      [:passthrough],
      maybe_create_event_async: fn user_trigger_tuple, _, _ -> user_trigger_tuple end
    }
  ]) do
    # Clean children on exit, otherwise DB calls from async tasks can be attempted
    clean_task_supervisor_children()

    Sanbase.Signal.Evaluator.Cache.clear()

    user = insert(:user)
    Sanbase.Auth.UserSettings.set_telegram_chat_id(user.id, 123_123_123_123)

    project = Sanbase.Factory.insert(:project)

    datetimes = generate_datetimes(~U[2019-01-01 00:00:00Z], "1d", 7)

    [
      user: user,
      project: project,
      datetimes: datetimes
    ]
  end

  test "signal with random metric works - above operation", context do
    %{project: project, user: user, datetimes: datetimes} = context

    trigger_settings = %{
      type: "metric_signal",
      metric: random_metric(),
      target: %{slug: project.coinmarketcap_id},
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

    data =
      Enum.zip(datetimes, [100, 100, 100, 100, 100, 100, 5000])
      |> Enum.map(&%{datetime: elem(&1, 0), value: elem(&1, 1)})

    with_mock Metric, [:passthrough], get: fn _, _, _, _, _ -> {:ok, data} end do
      [triggered] =
        MetricTriggerSettings.type()
        |> UserTrigger.get_active_triggers_by_type()
        |> Evaluator.run()

      assert triggered.id == trigger.id
    end
  end

  test "signal with random metric works - percent change operation", context do
    %{project: project, user: user, datetimes: datetimes} = context

    trigger_settings = %{
      type: "metric_signal",
      metric: random_metric(),
      target: %{slug: project.coinmarketcap_id},
      channel: "telegram",
      operation: %{percent_up: 100}
    }

    {:ok, trigger} =
      UserTrigger.create_user_trigger(user, %{
        title: "Generic title",
        is_public: true,
        cooldown: "12h",
        settings: trigger_settings
      })

    data =
      Enum.zip(datetimes, [100, 100, 100, 100, 100, 100, 500])
      |> Enum.map(&%{datetime: elem(&1, 0), value: elem(&1, 1)})

    with_mock Metric, [:passthrough], get: fn _, _, _, _, _ -> {:ok, data} end do
      [triggered] =
        MetricTriggerSettings.type()
        |> UserTrigger.get_active_triggers_by_type()
        |> Evaluator.run()

      assert triggered.id == trigger.id
    end
  end

  test "can create triggers with all available metrics", context do
    %{project: project, user: user} = context

    {:ok, metrics} = Metric.available_metrics()

    Enum.each(metrics, fn metric ->
      trigger_settings = %{
        type: "metric_signal",
        metric: metric,
        target: %{slug: project.coinmarketcap_id},
        channel: "telegram",
        operation: %{above: 300}
      }

      {:ok, _} =
        UserTrigger.create_user_trigger(user, %{
          title: "Generic title",
          is_public: true,
          cooldown: "12h",
          settings: trigger_settings
        })
    end)
  end

  test "cannot create triggers with random metrics", context do
    %{project: project, user: user} = context

    metrics = Enum.map(1..100, fn _ -> rand_str() end)

    Enum.each(metrics, fn metric ->
      trigger_settings = %{
        type: "metric_signal",
        metric: metric,
        target: %{slug: project.coinmarketcap_id},
        channel: "telegram",
        operation: %{above: 300}
      }

      assert capture_log(fn ->
               {:error, _} =
                 UserTrigger.create_user_trigger(user, %{
                   title: "Generic title",
                   is_public: true,
                   cooldown: "12h",
                   settings: trigger_settings
                 })
             end) =~ "UserTrigger struct is not valid"
    end)
  end

  defp random_metric() do
    {:ok, metrics} = Metric.available_metrics()
    metrics |> Enum.random()
  end
end
