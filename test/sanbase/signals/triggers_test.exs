defmodule Sanbase.Signals.TriggersTest do
  use Sanbase.DataCase, async: false

  import Sanbase.Factory

  alias Sanbase.Signals.UserTrigger

  test "create and get user trigger" do
    user = insert(:user)

    trigger_settings = %{
      type: "daily_active_addresses",
      target: "santiment",
      channel: "telegram",
      time_window: "1d",
      percent_threshold: 300.0,
      repeating: false,
      triggered?: false,
      payload: nil
    }

    {:ok, created_trigger} =
      UserTrigger.create_user_trigger(user, %{is_public: true, settings: trigger_settings})

    assert created_trigger.trigger.settings == trigger_settings

    trigger_id = created_trigger.trigger.id

    got_trigger = UserTrigger.get_trigger_by_id(user, trigger_id)

    assert got_trigger.settings |> Map.from_struct() == trigger_settings
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

    {:error, message} =
      UserTrigger.create_user_trigger(user, %{is_public: true, trigger: trigger})

    assert message == "Trigger structure is invalid"
  end

  test "try creating user trigger with required field in struct" do
    user = insert(:user)

    trigger = %{
      type: "daily_active_addresses",
      target: "santiment",
      time_window: "1d",
      percent_threshold: 300.0,
      repeating: false
    }

    {:error, message} =
      UserTrigger.create_user_trigger(user, %{is_public: true, trigger: trigger})

    assert message == "Trigger structure is invalid"
  end

  test "create user trigger with optional field missing" do
    user = insert(:user)

    trigger_settings = %{
      type: "price",
      target: "santiment",
      channel: "telegram",
      time_window: "1d",
      repeating: false
    }

    {:ok, created_trigger} =
      UserTrigger.create_user_trigger(user, %{is_public: true, settings: trigger_settings})

    assert trigger_settings.target == created_trigger.trigger.settings |> Map.get(:target)
  end

  test "create trigger when there is existing one" do
    user = insert(:user)

    trigger_settings1 = %{
      type: "daily_active_addresses",
      target: "santiment",
      channel: "telegram",
      time_window: "1d",
      percent_threshold: 300.0,
      repeating: false
    }

    insert(:user_triggers, user: user, trigger: %{is_public: true, settings: trigger_settings1})
    assert length(UserTrigger.triggers_for(user)) == 1

    trigger_settings2 = %{
      type: "price",
      target: "santiment",
      channel: "email",
      time_window: "1d",
      percent_threshold: 10.0,
      repeating: false
    }

    UserTrigger.create_user_trigger(user, %{is_public: true, settings: trigger_settings2})
    assert length(UserTrigger.triggers_for(user)) == 2
  end

  test "update trigger" do
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
      type: "price",
      target: "santiment",
      channel: "email",
      time_window: "1d",
      percent_threshold: 10.0,
      repeating: false
    }

    insert(:user_triggers, user: user, trigger: %{is_public: true, settings: trigger_settings1})
    insert(:user_triggers, user: user, trigger: %{is_public: true, settings: trigger_settings2})

    trigger_id = UserTrigger.triggers_for(user) |> hd |> Map.get(:id)

    updated_trigger = %{
      type: "daily_active_addresses",
      target: "santiment",
      channel: "telegram",
      time_window: "1d",
      percent_threshold: 300.0,
      repeating: true
    }

    UserTrigger.update_user_trigger(user, %{
      id: trigger_id,
      settings: updated_trigger,
      is_public: false
    })

    triggers = UserTrigger.triggers_for(user)

    assert length(triggers) == 2
    assert triggers |> hd |> Map.get(:settings) |> Map.get(:repeating) == true
  end

  test "update only common fields" do
    user = insert(:user)

    trigger_settings = %{
      type: "daily_active_addresses",
      target: "santiment",
      channel: "telegram",
      time_window: "1d",
      percent_threshold: 300.0,
      repeating: false
    }

    insert(:user_triggers, user: user, trigger: %{is_public: false, settings: trigger_settings})

    ut = UserTrigger.triggers_for(user)
    trigger_id = ut |> hd |> Map.get(:id)

    UserTrigger.update_user_trigger(user, %{id: trigger_id, is_public: true, cooldown: 3600})
    user_triggers = UserTrigger.triggers_for(user)

    trigger = user_triggers |> hd()
    assert trigger.is_public == true
    assert trigger.cooldown == 3600
  end
end
