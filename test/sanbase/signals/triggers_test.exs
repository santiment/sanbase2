defmodule Sanbase.Signals.TriggersTest do
  use Sanbase.DataCase, async: false

  import Sanbase.Factory
  import ExUnit.CaptureLog
  import Sanbase.TestHelpers

  alias Sanbase.Signals.UserTrigger

  test "create and get user trigger" do
    user = insert(:user)

    trigger_settings = %{
      type: "daily_active_addresses",
      target: "santiment",
      filtered_target_list: [],
      channel: "telegram",
      time_window: "1d",
      percent_threshold: 300.0,
      repeating: false,
      triggered?: false,
      payload: nil
    }

    {:ok, created_trigger} =
      UserTrigger.create_user_trigger(user, %{
        title: "Generic title",
        is_public: true,
        settings: trigger_settings
      })

    assert created_trigger.trigger.settings == trigger_settings

    trigger_id = created_trigger.trigger.id

    {:ok, %UserTrigger{trigger: trigger}} = UserTrigger.get_trigger_by_id(user, trigger_id)

    assert trigger.settings |> Map.from_struct() == trigger_settings
  end

  test "try creating user trigger with unknown type" do
    user = insert(:user)

    trigger_settings = %{
      type: "unknown",
      target: "santiment",
      channel: "telegram",
      time_window: "1d",
      percent_threshold: 300.0,
      repeating: false
    }

    {:error, message} =
      UserTrigger.create_user_trigger(user, %{
        title: "Generic title",
        is_public: true,
        settings: trigger_settings
      })

    assert message == "Trigger structure is invalid"
  end

  test "try creating user trigger with not valid icon url" do
    user = insert(:user)

    trigger_settings = %{
      type: "daily_active_addresses",
      target: "santiment",
      channel: "telegram",
      time_window: "1d",
      percent_threshold: 300.0,
      repeating: false
    }

    {:error, changeset} =
      UserTrigger.create_user_trigger(user, %{
        title: "Generic title",
        icon_url: "not_a_url",
        is_public: true,
        settings: trigger_settings
      })

    assert error_details(changeset) == %{trigger: %{icon_url: ["`not_a_url` is missing scheme"]}}
  end

  test "try creating user trigger with unknown channel" do
    user = insert(:user)

    trigger_settings = %{
      type: "daily_active_addresses",
      target: "santiment",
      channel: "unknown",
      time_window: "1d",
      percent_threshold: 300.0,
      repeating: false,
      triggered?: false,
      payload: nil
    }

    assert capture_log(fn ->
             {:error, message} =
               UserTrigger.create_user_trigger(user, %{
                 title: "Generic title",
                 is_public: true,
                 settings: trigger_settings
               })

             assert message =~ "Trigger structure is invalid"
           end) =~
             ~s/UserTrigger struct is not valid: [{:error, :channel, :by, \"\\\"unknown\\\" is not a valid notification channel"}]/
  end

  test "try creating user trigger with required field in struct" do
    user = insert(:user)

    settings = %{
      type: "daily_active_addresses",
      target: "santiment",
      time_window: "1d",
      percent_threshold: 300.0,
      repeating: false
    }

    {:error, message} =
      UserTrigger.create_user_trigger(user, %{
        title: "Generic title",
        is_public: true,
        settings: settings
      })

    assert message == "Trigger structure is invalid"
  end

  test "create user trigger with optional field missing" do
    user = insert(:user)

    trigger_settings = %{
      type: "price_percent_change",
      target: "santiment",
      percent_threshold: 20,
      channel: "telegram",
      time_window: "1d",
      repeating: false
    }

    title = "Some title"

    {:ok, created_trigger} =
      UserTrigger.create_user_trigger(user, %{
        title: title,
        is_public: true,
        settings: trigger_settings
      })

    assert trigger_settings.target == created_trigger.trigger.settings |> Map.get(:target)
    assert title = created_trigger.trigger.title
  end

  test "create trigger with icon and description" do
    user = insert(:user)

    trigger_settings = %{
      type: "price_percent_change",
      target: "santiment",
      percent_threshold: 20,
      channel: "telegram",
      time_window: "1d",
      repeating: false
    }

    title = "Generic title"
    description = "Some generic description"

    icon_url =
      "http://stage-sanbase-images.s3.amazonaws.com/uploads/_empowr-coinHY5QG72SCGKYWMN4AEJQ2BRDLXNWXECT.png"

    {:ok, created_trigger} =
      UserTrigger.create_user_trigger(user, %{
        title: title,
        description: description,
        icon_url: icon_url,
        is_public: true,
        settings: trigger_settings
      })

    assert trigger_settings.target == created_trigger.trigger.settings |> Map.get(:target)
    assert title = created_trigger.trigger.title
    assert description = created_trigger.trigger.description
    assert icon_url = created_trigger.trigger.icon_url
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

    insert(:user_triggers,
      user: user,
      trigger: %{title: "Generic title", is_public: true, settings: trigger_settings1}
    )

    assert length(UserTrigger.triggers_for(user)) == 1

    trigger_settings2 = %{
      type: "price_percent_change",
      target: "santiment",
      channel: "email",
      time_window: "1d",
      percent_threshold: 10.0,
      repeating: false
    }

    {:ok, _} =
      UserTrigger.create_user_trigger(user, %{
        title: "Generic title",
        is_public: true,
        settings: trigger_settings2
      })

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
      type: "price_percent_change",
      target: "santiment",
      channel: "email",
      time_window: "1d",
      percent_threshold: 10.0,
      repeating: false
    }

    insert(:user_triggers,
      user: user,
      trigger: %{title: "Generic title", is_public: true, settings: trigger_settings1}
    )

    insert(:user_triggers,
      user: user,
      trigger: %{title: "Generic title2", is_public: true, settings: trigger_settings2}
    )

    trigger_id = UserTrigger.triggers_for(user) |> hd |> Map.get(:id)

    updated_trigger = %{
      type: "daily_active_addresses",
      target: "santiment",
      channel: "telegram",
      time_window: "1d",
      percent_threshold: 200.0,
      repeating: true
    }

    new_title = "New title"
    new_description = "New description"

    new_icon_url =
      "http://stage-sanbase-images.s3.amazonaws.com/uploads/_empowr-coinHY5QG72SCGKYWMN4AEJQ2BRDLXNWXECT.png"

    {:ok, _} =
      UserTrigger.update_user_trigger(user, %{
        id: trigger_id,
        settings: updated_trigger,
        is_public: false,
        title: new_title,
        description: new_description,
        icon_url: new_icon_url
      })

    triggers = UserTrigger.triggers_for(user)

    assert length(triggers) == 2
    trigger = Enum.find(triggers, fn trigger -> trigger.id == trigger_id end)

    assert trigger |> Map.get(:settings) |> Map.get(:repeating) == true
    assert trigger.title == new_title
    assert trigger.description == new_description
    assert trigger.icon_url == new_icon_url
  end

  test "update only common fields" do
    user = insert(:user)

    trigger_settings = %{
      type: "daily_active_addresses",
      target: "santiment",
      channel: "telegram",
      time_window: "1d",
      percent_threshold: 200.0,
      repeating: false
    }

    insert(:user_triggers,
      user: user,
      trigger: %{title: "Generic title", is_public: false, settings: trigger_settings}
    )

    ut = UserTrigger.triggers_for(user)
    trigger_id = ut |> hd |> Map.get(:id)

    UserTrigger.update_user_trigger(user, %{id: trigger_id, is_public: true, cooldown: "1h"})
    user_triggers = UserTrigger.triggers_for(user)

    trigger = user_triggers |> hd()
    assert trigger.is_public == true
    assert trigger.cooldown == "1h"
  end
end
