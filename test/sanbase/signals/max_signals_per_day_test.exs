defmodule Sanbase.Signal.MaxSignalsPerDayTest do
  use Sanbase.DataCase, async: false

  import Sanbase.Factory
  import Sanbase.TestHelpers

  alias Sanbase.Signal.UserTrigger
  alias Sanbase.Signal.Trigger.MetricTriggerSettings

  setup do
    project = insert(:random_erc20_project)
    user = insert(:user, user_settings: %{settings: %{signal_notify_telegram: true}})
    Sanbase.Auth.UserSettings.set_telegram_chat_id(user.id, 123_123_123_123)

    trigger_settings = %{
      type: "metric_signal",
      metric: "active_addresses_24h",
      target: %{slug: project.slug},
      channel: "telegram",
      operation: %{above: 300}
    }

    create_trigger_fun = fn ->
      UserTrigger.create_user_trigger(user, %{
        title: "Generic title",
        is_public: true,
        cooldown: "12h",
        settings: trigger_settings
      })
    end

    # Create
    {:ok, trigger} = create_trigger_fun.()
    {:ok, _} = create_trigger_fun.()
    {:ok, _} = create_trigger_fun.()

    datetimes = generate_datetimes(~U[2019-01-01 00:00:00Z], "1d", 7)

    mock_fun =
      [
        fn -> {:ok, [%{datetime: datetimes |> List.first(), value: 100}]} end,
        fn -> {:ok, [%{datetiem: datetimes |> List.last(), value: 500}]} end
      ]
      |> Sanbase.Mock.wrap_consecutives(arity: 6)

    [
      trigger: trigger,
      project: project,
      user: user,
      mock_fun: mock_fun
    ]
  end

  test "does not send notifications after limit is reached", context do
    %{user: user, mock_fun: mock_fun} = context

    Sanbase.Auth.UserSettings.update_settings(user, %{
      signals_per_day_limit: %{"email" => 1, "telegram" => 1}
    })

    self_pid = self()

    Sanbase.Mock.prepare_mock(Sanbase.Clickhouse.MetricAdapter, :timeseries_data, mock_fun)
    |> Sanbase.Mock.prepare_mock(Sanbase.Telegram, :send_message, fn _user, text ->
      send(self_pid, {:telegram_to_self, text})
      :ok
    end)
    |> Sanbase.Mock.run_with_mocks(fn ->
      Sanbase.Signal.Scheduler.run_signal(MetricTriggerSettings)

      # Three triggers have been evaluted with the limit of signals per day being 3
      # One trigger succesfully sends
      # The second trigger fires the limit reached notification
      # The third trigger neither sends a notification nor re-sends the limit
      # reached notification
      assert_receive({:telegram_to_self, triggered_msg})
      assert triggered_msg =~ "Active Addresses for the last 24 hours is above 300"

      assert_receive({:telegram_to_self, limit_reached_msg})

      assert limit_reached_msg =~
               "Your maximum amount of telegram alert notifications per day has been reached"

      refute_receive({:telegram_to_self, _}, 1000)
    end)
  end
end
