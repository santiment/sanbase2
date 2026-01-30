defmodule Sanbase.Alert.TriggerSendingTest do
  use Sanbase.DataCase, async: false

  import Sanbase.Factory

  alias Sanbase.Alert.{UserTrigger, Scheduler}
  alias Sanbase.Alert.Trigger.MetricTriggerSettings

  setup do
    Sanbase.Cache.clear_all(:alerts_evaluator_cache)

    user =
      insert(:user,
        email: "test@example.com",
        user_settings: %{settings: %{alert_notify_telegram: true}}
      )

    Sanbase.Accounts.UserSettings.update_settings(user, %{alert_notify_email: true})
    Sanbase.Accounts.UserSettings.set_telegram_chat_id(user.id, 123_123_123_123)

    project = insert(:random_project)

    [user: user, project: project]
  end

  test "send to a webhook", context do
    %{user: user, project: project} = context

    {:ok, trigger} =
      create_trigger(user, project.slug,
        channel: [%{"webhook" => "https://example.com/webhook_url"}]
      )

    mock_fun =
      [
        fn -> {:ok, %{project.slug => 10}} end,
        fn -> {:ok, %{project.slug => 15}} end
      ]
      |> Sanbase.Mock.wrap_consecutives(arity: 4)

    Sanbase.Mock.prepare_mock(Sanbase.Metric, :aggregated_timeseries_data, mock_fun)
    |> Sanbase.Mock.prepare_mock2(
      &HTTPoison.post/3,
      {:ok, %HTTPoison.Response{status_code: 200, body: "OK"}}
    )
    |> Sanbase.Mock.run_with_mocks(fn ->
      Scheduler.run_alert(MetricTriggerSettings)

      trigger = trigger |> Sanbase.Repo.preload([:user])

      {:ok, user_trigger} = Sanbase.Alert.UserTrigger.by_user_and_id(trigger.user.id, trigger.id)

      last_triggered_dt =
        user_trigger.trigger.last_triggered
        |> Map.get(project.slug)
        |> Sanbase.DateTimeUtils.from_iso8601!()

      assert Sanbase.TestUtils.datetime_close_to(Timex.now(), last_triggered_dt, 60, :seconds)
    end)
  end

  defp create_trigger(user, slug, opts) do
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

    {:ok, trigger} =
      UserTrigger.create_user_trigger(user, %{
        title: "Generic title",
        is_public: true,
        cooldown: "12h",
        settings: trigger_settings
      })

    {:ok, trigger}
  end
end
