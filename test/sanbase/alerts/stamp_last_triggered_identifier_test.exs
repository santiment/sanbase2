defmodule Sanbase.Alert.StampLastTriggeredIdentifierTest do
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

  test "stamps atom identifiers under string keys", context do
    %{user: user, trigger: trigger} = context
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    assert :ok = UserTrigger.stamp_last_triggered(trigger.id, [:value, "bitcoin"], now)

    {:ok, user_trigger} = UserTrigger.by_user_and_id(user.id, trigger.id)

    assert user_trigger.trigger.last_triggered |> Map.keys() |> Enum.sort() ==
             ["bitcoin", "value"]
  end
end
