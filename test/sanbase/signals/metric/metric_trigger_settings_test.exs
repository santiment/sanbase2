defmodule Sanbase.Signal.MetricTriggerSettingsTest do
  use Sanbase.DataCase, async: false

  import Sanbase.Factory
  import Sanbase.TestHelpers
  import ExUnit.CaptureLog

  alias Sanbase.Signal.UserTrigger
  alias Sanbase.Signal.Evaluator
  alias Sanbase.Metric
  alias Sanbase.Signal.Trigger.MetricTriggerSettings

  @metrics_5m_min_interval Metric.available_metrics(min_interval_less_or_equal: "5m")
  setup_all_with_mocks([
    {
      Sanbase.Timeline.TimelineEvent,
      [:passthrough],
      maybe_create_event_async: fn user_trigger_tuple, _, _ -> user_trigger_tuple end
    }
  ]) do
    []
  end

  describe "metrics with text selector" do
    setup do
      # Clean children on exit, otherwise DB calls from async tasks can be attempted
      clean_task_supervisor_children()
      Sanbase.Signal.Evaluator.Cache.clear_all()
      datetimes = generate_datetimes(~U[2019-01-01 00:00:00Z], "1d", 7)

      user = insert(:user, user_settings: %{settings: %{signal_notify_telegram: true}})
      Sanbase.Auth.UserSettings.set_telegram_chat_id(user.id, 123_123_123_123)
      %{user: user, datetimes: datetimes}
    end

    test "signal with text selector works", context do
      %{user: user, datetimes: datetimes} = context

      trigger_settings = %{
        type: "metric_signal",
        metric: "social_volume_total",
        target: %{text: "random text"},
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

      # Return a fun with arity 5 that will return different results
      # for consecutive calls
      mock_fun =
        [
          fn -> {:ok, [%{datetime: datetimes |> List.first(), value: 100}]} end,
          fn -> {:ok, [%{datetiem: datetimes |> List.last(), value: 5000}]} end
        ]
        |> Sanbase.Mock.wrap_consecutives(arity: 6)

      Sanbase.Mock.prepare_mock(Sanbase.SocialData.MetricAdapter, :timeseries_data, mock_fun)
      |> Sanbase.Mock.run_with_mocks(fn ->
        [triggered] =
          MetricTriggerSettings.type()
          |> UserTrigger.get_active_triggers_by_type()
          |> Evaluator.run()

        assert triggered.id == trigger.id
      end)
    end
  end

  describe "metrics with slug selector" do
    setup do
      # Clean children on exit, otherwise DB calls from async tasks can be attempted
      clean_task_supervisor_children()

      Sanbase.Signal.Evaluator.Cache.clear_all()

      user = insert(:user)
      Sanbase.Auth.UserSettings.set_telegram_chat_id(user.id, 123_123_123_123)

      project = Sanbase.Factory.insert(:random_project)

      datetimes = generate_datetimes(~U[2019-01-01 00:00:00Z], "1d", 7)

      %{user: user, project: project, datetimes: datetimes}
    end

    test "signal with a metric works - above operation", context do
      %{project: project, user: user, datetimes: datetimes} = context

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

      # Return a fun with arity 5 that will return different results
      # for consecutive calls
      mock_fun =
        [
          fn -> {:ok, [%{datetime: datetimes |> List.first(), value: 100}]} end,
          fn -> {:ok, [%{datetiem: datetimes |> List.last(), value: 5000}]} end
        ]
        |> Sanbase.Mock.wrap_consecutives(arity: 6)

      Sanbase.Mock.prepare_mock(Sanbase.Clickhouse.MetricAdapter, :timeseries_data, mock_fun)
      |> Sanbase.Mock.run_with_mocks(fn ->
        [triggered] =
          MetricTriggerSettings.type()
          |> UserTrigger.get_active_triggers_by_type()
          |> Evaluator.run()

        assert triggered.id == trigger.id
      end)
    end

    test "signal with metric works - percent change operation", context do
      %{project: project, user: user, datetimes: datetimes} = context

      trigger_settings = %{
        type: "metric_signal",
        metric: "active_addresses_24h",
        target: %{slug: project.slug},
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

      mock_fun =
        [
          fn -> {:ok, [%{datetime: datetimes |> List.first(), value: 100}]} end,
          fn -> {:ok, [%{datetiem: datetimes |> List.last(), value: 500}]} end
        ]
        |> Sanbase.Mock.wrap_consecutives(arity: 6)

      Sanbase.Mock.prepare_mock(Sanbase.Clickhouse.MetricAdapter, :timeseries_data, mock_fun)
      |> Sanbase.Mock.run_with_mocks(fn ->
        [triggered] =
          MetricTriggerSettings.type()
          |> UserTrigger.get_active_triggers_by_type()
          |> Evaluator.run()

        assert triggered.id == trigger.id
      end)
    end

    test "can create triggers with all available metrics with min interval less than 5 min",
         context do
      %{project: project, user: user} = context

      Enum.each(@metrics_5m_min_interval, fn metric ->
        trigger_settings = %{
          type: "metric_signal",
          metric: metric,
          target: %{slug: project.slug},
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
          target: %{slug: project.slug},
          channel: "telegram",
          operation: %{above: 300}
        }

        assert capture_log(fn ->
                 {:error, error_msg} =
                   UserTrigger.create_user_trigger(user, %{
                     title: "Generic title",
                     is_public: true,
                     cooldown: "12h",
                     settings: trigger_settings
                   })

                 assert error_msg =~ "not supported or is mistyped"
               end)
      end)
    end
  end
end
