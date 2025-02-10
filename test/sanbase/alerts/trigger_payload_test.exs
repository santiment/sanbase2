defmodule Sanbase.Alert.TriggerPayloadTest do
  use Sanbase.DataCase, async: false

  import Sanbase.Factory

  alias Sanbase.Accounts.UserSettings
  alias Sanbase.Alert.Scheduler
  alias Sanbase.Alert.Trigger.MetricTriggerSettings
  alias Sanbase.Alert.UserTrigger

  setup do
    Sanbase.Cache.clear_all(:alerts_evaluator_cache)

    user =
      insert(:user,
        email: "test@example.com",
        user_settings: %{settings: %{alert_notify_telegram: true}}
      )

    UserSettings.update_settings(user, %{alert_notify_email: true})
    UserSettings.set_telegram_chat_id(user.id, 123_123_123_123)

    project = insert(:random_project)

    [user: user, project: project]
  end

  test "human readable numbers between 1000 and 1,000,000", context do
    %{user: user, project: project} = context

    {:ok, _trigger} = create_trigger(user, project.slug)

    self_pid = self()

    mock_fun =
      Sanbase.Mock.wrap_consecutives(
        [fn -> {:ok, %{project.slug => 100}} end, fn -> {:ok, %{project.slug => 10_456}} end],
        arity: 4
      )

    Sanbase.Metric
    |> Sanbase.Mock.prepare_mock(:aggregated_timeseries_data, mock_fun)
    |> Sanbase.Mock.prepare_mock(Sanbase.Telegram, :send_message, fn _user, text ->
      send(self_pid, {:telegram_to_self, text})
      {:ok, "OK"}
    end)
    |> Sanbase.Mock.run_with_mocks(fn ->
      Scheduler.run_alert(MetricTriggerSettings)

      assert_receive({:telegram_to_self, message}, 1000)
      assert message =~ "10,456.00"
    end)
  end

  test "human readable numbers above 1,000,000", context do
    %{user: user, project: project} = context

    {:ok, _trigger} = create_trigger(user, project.slug)

    self_pid = self()

    mock_fun =
      Sanbase.Mock.wrap_consecutives(
        [fn -> {:ok, %{project.slug => 10}} end, fn -> {:ok, %{project.slug => 9_231_100_456}} end],
        arity: 4
      )

    Sanbase.Metric
    |> Sanbase.Mock.prepare_mock(:aggregated_timeseries_data, mock_fun)
    |> Sanbase.Mock.prepare_mock(Sanbase.Telegram, :send_message, fn _user, text ->
      send(self_pid, {:telegram_to_self, text})
      {:ok, "OK"}
    end)
    |> Sanbase.Mock.run_with_mocks(fn ->
      Scheduler.run_alert(MetricTriggerSettings)

      assert_receive({:telegram_to_self, message}, 1000)
      assert message =~ "9.23 Billion"
    end)
  end

  test "payload is extended", context do
    %{user: user, project: project} = context

    {:ok, trigger} = create_trigger(user, project.slug)

    self_pid = self()

    mock_fun =
      Sanbase.Mock.wrap_consecutives([fn -> {:ok, %{project.slug => 10}} end, fn -> {:ok, %{project.slug => 5}} end],
        arity: 4
      )

    Sanbase.Metric
    |> Sanbase.Mock.prepare_mock(:aggregated_timeseries_data, mock_fun)
    |> Sanbase.Mock.prepare_mock(Sanbase.Telegram, :send_message, fn _user, text ->
      send(self_pid, {:telegram_to_self, text})
      {:ok, "OK"}
    end)
    |> Sanbase.Mock.run_with_mocks(fn ->
      Scheduler.run_alert(MetricTriggerSettings)
      assert_receive({:telegram_to_self, message}, 1000)
      assert message =~ SanbaseWeb.Endpoint.show_alert_url(trigger.id)
    end)
  end

  test "metric payload details", context do
    %{user: user, project: project} = context

    {:ok, _trigger} =
      create_trigger(user, project.slug, metric: "active_addresses_24h", time_window: "2d")

    self_pid = self()

    mock_fun =
      Sanbase.Mock.wrap_consecutives([fn -> {:ok, %{project.slug => 10}} end, fn -> {:ok, %{project.slug => 5}} end],
        arity: 4
      )

    Sanbase.Metric
    |> Sanbase.Mock.prepare_mock(:aggregated_timeseries_data, mock_fun)
    |> Sanbase.Mock.prepare_mock(Sanbase.Telegram, :send_message, fn _user, text ->
      send(self_pid, {:telegram_to_self, text})
      {:ok, "OK"}
    end)
    |> Sanbase.Mock.prepare_mock2(&DateTime.utc_now/0, ~U[2021-01-10 15:00:00Z])
    |> Sanbase.Mock.run_with_mocks(fn ->
      Scheduler.run_alert(MetricTriggerSettings)

      assert_receive({:telegram_to_self, message}, 1000)

      assert message =~
               "Generated by the value of the metric at 10 Jan 2021 15:00 UTC"
    end)
  end

  # TODO: Move to a `trigger_sending_test.exs`
  test "send to a webhook", context do
    %{user: user, project: project} = context

    {:ok, trigger} =
      create_trigger(user, project.slug, channel: [%{"webhook" => "https://example.com/webhook_url"}])

    mock_fun =
      Sanbase.Mock.wrap_consecutives([fn -> {:ok, %{project.slug => 10}} end, fn -> {:ok, %{project.slug => 15}} end],
        arity: 4
      )

    Sanbase.Metric
    |> Sanbase.Mock.prepare_mock(:aggregated_timeseries_data, mock_fun)
    |> Sanbase.Mock.prepare_mock2(
      &HTTPoison.post/3,
      {:ok, %HTTPoison.Response{status_code: 200, body: "OK"}}
    )
    |> Sanbase.Mock.run_with_mocks(fn ->
      Scheduler.run_alert(MetricTriggerSettings)

      trigger = Sanbase.Repo.preload(trigger, [:user])

      {:ok, user_trigger} = Sanbase.Alert.UserTrigger.by_user_and_id(trigger.user.id, trigger.id)

      last_triggered_dt =
        user_trigger.trigger.last_triggered
        |> Map.get(project.slug)
        |> Sanbase.DateTimeUtils.from_iso8601!()

      # Last triggered is rounded to minutes
      assert Sanbase.TestUtils.datetime_close_to(DateTime.utc_now(), last_triggered_dt, 60, :seconds)
    end)
  end

  # Private functions

  defp create_trigger(user, slug, opts \\ []) do
    metric = Keyword.get(opts, :metric, "active_addresses_24h")
    time_window = Keyword.get(opts, :time_window, "1d")
    channel = Keyword.get(opts, :channel, ["telegram"])

    trigger_settings = %{
      type: "metric_signal",
      metric: metric,
      target: %{slug: slug},
      channel: channel,
      time_window: time_window,
      operation: %{above_or_equal: 5}
    }

    {:ok, _trigger} =
      UserTrigger.create_user_trigger(user, %{
        title: "Generic title",
        is_public: true,
        cooldown: "12h",
        settings: trigger_settings
      })
  end
end
