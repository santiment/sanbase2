defmodule Sanbase.Signals.TriggersTest do
  use Sanbase.DataCase, async: false

  import Sanbase.Factory

  alias Sanbase.Signals.{UserTriggers, Trigger}

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

    {:ok, triggers} = UserTriggers.create_trigger(user, trigger)

    assert triggers |> hd |> Map.get(:trigger) |> Map.from_struct() == trigger

    trigger_id = triggers |> hd |> Map.get(:id)

    created_trigger =
      UserTriggers.get_trigger(user, trigger_id)
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

    {:error, message} = UserTriggers.create_trigger(user, trigger)
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

    {:error, message} = UserTriggers.create_trigger(user, trigger)
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

    {:ok, triggers} = UserTriggers.create_trigger(user, trigger)

    assert trigger.target ==
             triggers |> hd |> Map.get(:trigger) |> Map.from_struct() |> Map.get(:target)
  end
end
