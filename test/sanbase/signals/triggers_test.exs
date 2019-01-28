defmodule Sanbase.Signals.TriggersTest do
  use Sanbase.DataCase, async: false

  import Sanbase.Factory

  alias Sanbase.Signals.UserTrigger

  test "create and get user trigger" do
    user = insert(:user)

    trigger = %{
      type: "daa",
      target: "santiment",
      channel: "telegram",
      time_window: "1d",
      percent_threshold: 300.0,
      repeating: false
    }

    {:ok, triggers} = UserTrigger.create_trigger(user, %{is_public: true, trigger: trigger})

    assert triggers |> hd |> Map.get(:trigger) |> Map.from_struct() == trigger

    trigger_id = triggers |> hd |> Map.get(:id)

    created_trigger =
      UserTrigger.get_trigger(user, trigger_id)
      |> Map.get(:trigger)
      |> Map.from_struct()

    assert trigger == created_trigger
  end

  test "try creating user trigger with unknown type" do
    user = insert(:user)

    trigger = %{
      type: "unknown",
      target: "santiment",
      channel: "telegram",
      time_window: "1d",
      percent_threshold: 300.0,
      repeating: false
    }

    {:error, message} = UserTrigger.create_trigger(user, %{is_public: true, trigger: trigger})
    assert message == "Trigger structure is invalid"
  end

  test "try creating user trigger with required field in struct" do
    user = insert(:user)

    trigger = %{
      type: "daa",
      target: "santiment",
      time_window: "1d",
      percent_threshold: 300.0,
      repeating: false
    }

    {:error, message} = UserTrigger.create_trigger(user, %{is_public: true, trigger: trigger})
    assert message == "Trigger structure is invalid"
  end

  test "create user trigger with optional field missing" do
    user = insert(:user)

    trigger = %{
      type: "price",
      target: "santiment",
      channel: "telegram",
      time_window: "1d",
      repeating: false
    }

    {:ok, triggers} = UserTrigger.create_trigger(user, %{is_public: true, trigger: trigger})

    assert trigger.target ==
             triggers |> hd |> Map.get(:trigger) |> Map.from_struct() |> Map.get(:target)
  end

  test "create trigger when there is existing one" do
    user = insert(:user)

    trigger1 = %{
      type: "daa",
      target: "santiment",
      channel: "telegram",
      time_window: "1d",
      percent_threshold: 300.0,
      repeating: false
    }

    insert(:user_triggers, user: user, triggers: [%{is_public: true, trigger: trigger1}])
    assert length(UserTrigger.triggers_for(user)) == 1

    trigger2 = %{
      type: "price",
      target: "santiment",
      channel: "email",
      time_window: "1d",
      percent_threshold: 10.0,
      repeating: false
    }

    UserTrigger.create_trigger(user, %{is_public: true, trigger: trigger2})
    assert length(UserTrigger.triggers_for(user)) == 2
  end

  test "update trigger" do
    user = insert(:user)

    trigger1 = %{
      type: "daa",
      target: "santiment",
      channel: "telegram",
      time_window: "1d",
      percent_threshold: 300.0,
      repeating: false
    }

    trigger2 = %{
      type: "price",
      target: "santiment",
      channel: "email",
      time_window: "1d",
      percent_threshold: 10.0,
      repeating: false
    }

    insert(:user_triggers,
      user: user,
      triggers: [%{is_public: true, trigger: trigger1}, %{is_public: true, trigger: trigger2}]
    )

    ut = UserTrigger.triggers_for(user)

    trigger_id = ut |> hd |> Map.get(:id)

    updated_trigger = %{
      type: "daa",
      target: "santiment",
      channel: "telegram",
      time_window: "1d",
      percent_threshold: 300.0,
      repeating: true
    }

    UserTrigger.update_trigger(user, %{
      id: trigger_id,
      trigger: updated_trigger,
      is_public: false
    })

    user_triggers = UserTrigger.triggers_for(user)

    assert length(user_triggers) == 2
    assert user_triggers |> hd |> Map.get(:trigger) |> Map.get(:repeating) == true
  end

  test "update only common is_public field" do
    user = insert(:user)

    trigger1 = %{
      type: "daa",
      target: "santiment",
      channel: "telegram",
      time_window: "1d",
      percent_threshold: 300.0,
      repeating: false
    }

    insert(:user_triggers, user: user, triggers: [%{is_public: false, trigger: trigger1}])

    ut = UserTrigger.triggers_for(user)
    trigger_id = ut |> hd |> Map.get(:id)

    UserTrigger.update_trigger(user, %{id: trigger_id, is_public: true})
    user_triggers = UserTrigger.triggers_for(user)

    assert user_triggers |> hd |> Map.get(:is_public) == true
  end
end
