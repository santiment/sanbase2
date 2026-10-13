defmodule Sanbase.Alert.MetricTextTargetIdentifierTest do
  # The social metric adapter can return the value of a text target in any of these shapes
  use Sanbase.DataCase,
    async: false,
    parameterize: [%{shape: :map}, %{shape: :number}, %{shape: :keyed}]

  import Sanbase.Factory

  alias Sanbase.Alert.{Scheduler, Trigger, UserTrigger}
  alias Sanbase.Alert.Trigger.MetricTriggerSettings

  setup do
    Sanbase.Cache.clear_all()
    Sanbase.Cache.clear_all(:alerts_evaluator_cache)

    user = insert(:user, user_settings: %{settings: %{alert_notify_telegram: true}})
    Sanbase.Accounts.UserSettings.set_telegram_chat_id(user.id, 123_123_123_123)

    {:ok, trigger} =
      UserTrigger.create_user_trigger(user, %{
        title: "Social volume alert",
        is_public: false,
        cooldown: "12h",
        settings: %{
          type: "metric_signal",
          metric: "social_volume_total",
          target: %{text: "bitcoin"},
          channel: "telegram",
          time_window: "1d",
          operation: %{above: 300}
        }
      })

    %{user: user, trigger: trigger}
  end

  test "text target alert is keyed by the search text and respects the cooldown", context do
    %{user: user, trigger: trigger, shape: shape} = context
    test_pid = self()

    metric_mock =
      [fn -> {:ok, wrap(shape, 100)} end, fn -> {:ok, wrap(shape, 5000)} end]
      |> Sanbase.Mock.wrap_consecutives(arity: 4)

    Sanbase.Mock.prepare_mock(Sanbase.Metric, :aggregated_timeseries_data, metric_mock)
    |> Sanbase.Mock.prepare_mock(Sanbase.Telegram, :send_message, fn _user, text ->
      send(test_pid, {:telegram_sent, text})
      {:ok, ~s({"result": {}})}
    end)
    |> Sanbase.Mock.run_with_mocks(fn ->
      Scheduler.run_alert(MetricTriggerSettings)

      assert_receive {:telegram_sent, text}
      assert text =~ "bitcoin"
      refute text =~ "'value'"

      {:ok, user_trigger} = UserTrigger.by_user_and_id(user.id, trigger.id)
      assert Map.keys(user_trigger.trigger.last_triggered) == ["bitcoin"]
      assert Trigger.has_cooldown?(user_trigger.trigger, "bitcoin")

      # The second run is within the cooldown - nothing is sent
      Scheduler.run_alert(MetricTriggerSettings)
      refute_receive {:telegram_sent, _}
    end)
  end

  defp wrap(:map, value), do: %{value: value}
  defp wrap(:number, value), do: value
  defp wrap(:keyed, value), do: %{"bitcoin" => value}
end
