defmodule Sanbase.Signals.EvaluatorTest do
  use Sanbase.DataCase, async: false

  import Sanbase.Factory
  import Mock

  alias Sanbase.Signals.UserTrigger
  alias Sanbase.Signals.Evaluator
  alias Sanbase.Signals.Trigger.DailyActiveAddressesTriggerSettings

  setup do
    Sanbase.Signals.Evaluator.Cache.clear()
    user = insert(:user)

    trigger_settings1 = %{
      type: "daily_active_addresses",
      target: "santiment",
      channel: "telegram",
      time_window: "1d",
      percent_threshold: 300.0,
      repeating: false
    }

    trigger_settings2 = %{
      type: "daily_active_addresses",
      target: "santiment",
      channel: "telegram",
      time_window: "1d",
      percent_threshold: 200.0,
      repeating: false
    }

    {:ok, trigger1} =
      UserTrigger.create_user_trigger(user, %{
        is_public: true,
        cooldown: 60,
        settings: trigger_settings1
      })

    {:ok, trigger2} =
      UserTrigger.create_user_trigger(user, %{
        is_public: true,
        cooldown: 60,
        settings: trigger_settings2
      })

    [
      user: user,
      trigger1: trigger1,
      trigger2: trigger2
    ]
  end

  test "evaluate triggers all criteria match", context do
    with_mock DailyActiveAddressesTriggerSettings, [:passthrough],
      get_data: fn _ ->
        {100, 20}
      end do
      [triggered1, triggered2 | rest] =
        DailyActiveAddressesTriggerSettings.type()
        |> UserTrigger.get_triggers_by_type()
        |> Evaluator.run()

      # 2 signals triggered
      assert length(rest) == 0
      assert context.trigger1.id == triggered1.id
      assert context.trigger2.id == triggered2.id
    end
  end

  test "evaluate triggers some criteria match", context do
    with_mock DailyActiveAddressesTriggerSettings, [:passthrough],
      get_data: fn _ ->
        {100, 30}
      end do
      [triggered | rest] =
        DailyActiveAddressesTriggerSettings.type()
        |> UserTrigger.get_triggers_by_type()
        |> Evaluator.run()

      # 1 signal triggered
      assert length(rest) == 0
      assert context.trigger2.id == triggered.id
    end
  end

  test "evaluate triggers no criteria match", _context do
    with_mock DailyActiveAddressesTriggerSettings, [:passthrough],
      get_data: fn _ ->
        {100, 100}
      end do
      triggered =
        DailyActiveAddressesTriggerSettings.type()
        |> UserTrigger.get_triggers_by_type()
        |> Evaluator.run()

      # 0 signals triggered
      assert length(triggered) == 0
    end
  end
end
