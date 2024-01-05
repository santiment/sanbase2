defmodule Sanbase.Alert.DailyMetricTriggerSettingsTest do
  use Sanbase.DataCase, async: false

  import Sanbase.Factory
  import Sanbase.TestHelpers
  import ExUnit.CaptureLog

  alias Sanbase.Alert.UserTrigger
  alias Sanbase.Alert.Evaluator
  alias Sanbase.Metric
  alias Sanbase.Alert.Trigger.DailyMetricTriggerSettings

  @metrics_1d_min_interval Metric.available_metrics(
                             filter: :min_interval_greater_or_equal,
                             filter_interval: "1d"
                           )
  setup_all_with_mocks([
    {
      Sanbase.Timeline.TimelineEvent,
      [:passthrough],
      maybe_create_event_async: fn user_trigger_tuple, _, _ -> user_trigger_tuple end
    }
  ]) do
    []
  end

  setup do
    # Clean children on exit, otherwise DB calls from async tasks can be attempted
    clean_task_supervisor_children()

    Sanbase.Cache.clear_all(:alerts_evaluator_cache)

    user = insert(:user)
    Sanbase.Accounts.UserSettings.set_telegram_chat_id(user.id, 123_123_123_123)

    project = Sanbase.Factory.insert(:random_project)

    %{user: user, project: project}
  end

  test "signal with a metric works - above operation", context do
    %{project: project, user: user} = context

    trigger_settings = %{
      type: "daily_metric_signal",
      metric: "mean_dollar_invested_age",
      target: %{slug: project.slug},
      channel: "telegram",
      operation: %{above: 300}
    }

    {:ok, trigger} =
      UserTrigger.create_user_trigger(user, %{
        title: "Generic title",
        is_public: true,
        cooldown: "1d",
        settings: trigger_settings
      })

    # Return a fun with arity 5 that will return different results
    # for consecutive calls
    mock_fun =
      [
        fn -> {:ok, %{project.slug => 100}} end,
        fn -> {:ok, %{project.slug => 5000}} end
      ]
      |> Sanbase.Mock.wrap_consecutives(arity: 5)

    Sanbase.Mock.prepare_mock(
      Sanbase.Clickhouse.MetricAdapter,
      :aggregated_timeseries_data,
      mock_fun
    )
    |> Sanbase.Mock.run_with_mocks(fn ->
      [triggered] =
        DailyMetricTriggerSettings.type()
        |> UserTrigger.get_active_triggers_by_type()
        |> Evaluator.run()

      assert triggered.id == trigger.id
    end)
  end

  test "signal with metric works - percent change operation", context do
    %{project: project, user: user} = context

    trigger_settings = %{
      type: "daily_metric_signal",
      metric: "mean_dollar_invested_age",
      target: %{slug: project.slug},
      channel: "telegram",
      operation: %{percent_up: 100}
    }

    {:ok, trigger} =
      UserTrigger.create_user_trigger(user, %{
        title: "Generic title",
        is_public: true,
        cooldown: "1d",
        settings: trigger_settings
      })

    mock_fun =
      [
        fn -> {:ok, %{project.slug => 100}} end,
        fn -> {:ok, %{project.slug => 500}} end
      ]
      |> Sanbase.Mock.wrap_consecutives(arity: 5)

    Sanbase.Mock.prepare_mock(
      Sanbase.Clickhouse.MetricAdapter,
      :aggregated_timeseries_data,
      mock_fun
    )
    |> Sanbase.Mock.run_with_mocks(fn ->
      [triggered] =
        DailyMetricTriggerSettings.type()
        |> UserTrigger.get_active_triggers_by_type()
        |> Evaluator.run()

      assert triggered.id == trigger.id
    end)
  end

  test "can create triggers with all available metrics with min interval >= 1d",
       context do
    %{project: project, user: user} = context

    @metrics_1d_min_interval
    |> Enum.shuffle()
    |> Enum.take(100)
    |> Enum.each(fn metric ->
      trigger_settings = %{
        type: "daily_metric_signal",
        metric: metric,
        target: %{slug: project.slug},
        channel: "telegram",
        operation: %{above: 300}
      }

      {:ok, _} =
        UserTrigger.create_user_trigger(user, %{
          title: "Generic title",
          is_public: true,
          cooldown: "1d",
          settings: trigger_settings
        })
    end)
  end

  test "cannot create triggers with random metrics", context do
    %{project: project, user: user} = context

    metrics = Enum.map(1..100, fn _ -> rand_str() end)

    Enum.each(metrics, fn metric ->
      trigger_settings = %{
        type: "daily_metric_signal",
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
                   cooldown: "1d",
                   settings: trigger_settings
                 })

               assert error_msg =~ "not supported, is deprecated or is mistyped"
             end)
    end)
  end
end
