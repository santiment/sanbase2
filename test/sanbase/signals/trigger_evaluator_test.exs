defmodule Sanbase.Signals.EvaluatorTest do
  use Sanbase.DataCase, async: false

  import Sanbase.Factory

  alias Sanbase.Signals.UserTrigger
  alias Sanbase.Signals.Evaluator

  setup do
    user = insert(:user)

    trigger1 = %{
      type: "daily_active_addresses",
      target: "santiment",
      channel: "telegram",
      time_window: "1d",
      percent_threshold: 300.0,
      repeating: false,
      cooldown: 5
    }

    trigger2 = %{
      type: "daily_active_addresses",
      target: "santiment",
      channel: "telegram",
      time_window: "1d",
      percent_threshold: 250.0,
      repeating: false,
      cooldown: 5
    }

    {:ok, _} = UserTrigger.create_trigger(user, %{is_public: true, trigger: trigger1})
    {:ok, triggers} = UserTrigger.create_trigger(user, %{is_public: true, trigger: trigger2})

    [
      triggers: triggers,
      user: user
    ]
  end

  test "evaluate triggers", context do
    Evaluator.run(context.triggers)
    IO.inspect(Sanbase.Signals.UserTrigger.triggers_for(context.user))
    Sanbase.Repo.get(User)
    assert 1 == 2
  end
end
