defmodule Sanbase.Alert.StampLastTriggeredIdentifierTest do
  # Reproduces SANBASE-BACKEND-PROD-GA6: metric alerts with a `%{text: ...}`
  # target (social metrics) get their data from
  # SocialData.MetricAdapter.aggregated_timeseries_data/5 as `%{value: v}`, so
  # MetricTriggerHelper.unfold_result/1 produces the atom identifier `:value`.
  # UserTrigger.stamp_last_triggered/3 binds the identifier as a raw text
  # param, so Postgrex raises DBConnection.EncodeError ("expected a binary,
  # got :value") right after the alert was sent.
  use Sanbase.DataCase, async: false

  import Sanbase.Factory

  alias Sanbase.Alert.UserTrigger

  setup do
    user = insert(:user)

    {:ok, trigger} =
      UserTrigger.create_user_trigger(user, %{
        title: "Social volume alert",
        is_public: false,
        cooldown: "12h",
        settings: %{
          type: "metric_signal",
          metric: "social_volume_total",
          target: %{text: "bitcoin"},
          channel: ["telegram"],
          time_window: "1d",
          operation: %{above_or_equal: 5}
        }
      })

    %{user: user, trigger: trigger}
  end

  test "stamps an atom identifier (:value) as its string form", context do
    %{user: user, trigger: trigger} = context
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    assert :ok = UserTrigger.stamp_last_triggered(trigger.id, :value, now)

    {:ok, user_trigger} = UserTrigger.by_user_and_id(user.id, trigger.id)
    assert Map.has_key?(user_trigger.trigger.last_triggered, "value")
  end

  test "stamps a list containing atom identifiers", context do
    %{user: user, trigger: trigger} = context
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    assert :ok = UserTrigger.stamp_last_triggered(trigger.id, [:value, "bitcoin"], now)

    {:ok, user_trigger} = UserTrigger.by_user_and_id(user.id, trigger.id)

    assert user_trigger.trigger.last_triggered |> Map.keys() |> Enum.sort() ==
             ["bitcoin", "value"]
  end
end
