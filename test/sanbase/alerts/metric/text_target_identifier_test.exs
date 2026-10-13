defmodule Sanbase.Alert.MetricTextTargetIdentifierTest do
  # Text target alerts must be keyed (cooldown, message) by the search text, not :value,
  # whichever shape the social metric adapter returns the value in
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
    run_text_alert(context, {:ok, wrap(context.shape, 100)}, {:ok, wrap(context.shape, 5000)})
  end

  defp run_text_alert(context, first_result, second_result) do
    %{user: user, trigger: trigger} = context
    test_pid = self()

    metric_mock =
      [fn -> first_result end, fn -> second_result end]
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
      assert user_trigger.trigger.last_triggered |> Map.keys() == ["bitcoin"]
      assert Trigger.has_cooldown?(user_trigger.trigger, "bitcoin")

      # The second run is within the cooldown - nothing is sent.
      Scheduler.run_alert(MetricTriggerSettings)
      refute_receive {:telegram_sent, _}
    end)
  end

  defp wrap(:map, value), do: %{value: value}
  defp wrap(:number, value), do: value
  defp wrap(:keyed, value), do: %{"bitcoin" => value}
end
