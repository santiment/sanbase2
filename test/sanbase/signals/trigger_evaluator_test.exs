defmodule Sanbase.Signals.EvaluatorTest do
  use Sanbase.DataCase, async: false

  import Sanbase.Factory
  import Mock

  alias Sanbase.Signals.UserTrigger
  alias Sanbase.Signals.Evaluator
  alias Sanbase.Signals.DailyActiveAddressesTriggerSettings

  setup do
    user = insert(:user)

    trigger1 = %{
      type: "daily_active_addresses",
      target: "santiment",
      channel: "telegram",
      time_window: "1d",
      percent_threshold: 300.0,
      repeating: false
    }

    trigger2 = %{
      type: "daily_active_addresses",
      target: "santiment",
      channel: "telegram",
      time_window: "1d",
      percent_threshold: 250.0,
      repeating: false
    }

    {:ok, _} =
      UserTrigger.create_user_trigger(user, %{is_public: true, cooldown: "1h", trigger: trigger1})

    {:ok, _} =
      UserTrigger.create_user_trigger(user, %{is_public: true, cooldown: "1h", trigger: trigger2})

    [
      user: user
    ]
  end

  test "evaluate triggers", context do
    with_mock DailyActiveAddressesTriggerSettings, :get_data, fn _, _ ->
      {100, 20}
    end do
      DailyActiveAddressesTriggerSettings.type()
      |> UserTrigger.triggers_by_type()
      |> Evaluator.run(context.triggers)
      |> IO.inspect()

      assert 1 == 2
    end
  end
end
