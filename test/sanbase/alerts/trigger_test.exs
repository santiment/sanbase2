defmodule Sanbase.Alert.TriggersTest do
  use Sanbase.DataCase, async: false

  import Sanbase.Factory
  import ExUnit.CaptureLog
  import Sanbase.TestHelpers
  import Sanbase.MapUtils
  import Sanbase.Utils.ErrorHandling, only: [changeset_errors: 1]

  alias Sanbase.Alert.UserTrigger
  alias Sanbase.Timeline.TimelineEvent

  setup do
    clean_task_supervisor_children()
  end

  test "create and get user trigger" do
    user = insert(:user)

    trigger_settings = %{
      type: "metric_signal",
      metric: "active_addresses_24h",
      target: %{slug: ["santiment", "bitcoin"]},
      channel: "telegram",
      time_window: "1d",
      operation: %{percent_up: 300.0}
    }

    {:ok, created_trigger} =
      UserTrigger.create_user_trigger(user, %{
        title: "Generic title",
        is_public: true,
        settings: trigger_settings
      })

    assert_receive({_, {:ok, %TimelineEvent{}}})

    assert TimelineEvent |> Sanbase.Repo.all() |> length() == 1

    assert created_trigger.trigger.settings == trigger_settings

    trigger_id = created_trigger.id

    {:ok, %UserTrigger{trigger: trigger}} = UserTrigger.by_user_and_id(user.id, trigger_id)

    settings = trigger.settings |> Map.from_struct()
    assert drop_diff_keys(settings, trigger_settings) == trigger_settings
  end

  test "try creating user trigger with unknown type" do
    user = insert(:user)

    trigger_settings = %{
      type: "unknown",
      target: %{slug: "santiment"},
      channel: "telegram",
      time_window: "1d",
      operation: %{percent_up: 300.0}
    }

    assert capture_log(fn ->
             {:error, message} =
               UserTrigger.create_user_trigger(user, %{
                 title: "Generic title",
                 is_public: true,
                 settings: trigger_settings
               })

             assert message ==
                      ~s/Trigger structure is invalid. Key `settings` is not valid. Reason: "The trigger settings type 'unknown' is not a valid type."/
           end) =~
             ~s/UserTrigger struct is not valid. Reason: "The trigger settings type 'unknown' is not a valid type./
  end

  test "try creating user trigger with not valid icon url" do
    user = insert(:user)

    trigger_settings = %{
      type: "metric_signal",
      metric: "active_addresses_24h",
      target: %{slug: "santiment"},
      channel: "telegram",
      time_window: "1d",
      operation: %{percent_up: 300.0}
    }

    {:error, changeset} =
      UserTrigger.create_user_trigger(user, %{
        title: "Generic title",
        icon_url: "not_a_url",
        is_public: true,
        settings: trigger_settings
      })

    assert changeset_errors(changeset) == %{
             trigger: %{
               icon_url: [
                 "URL 'not_a_url' is missing a scheme (e.g. https)"
               ]
             }
           }
  end

  test "try creating user trigger with invalid webhook_url" do
    user = insert(:user)

    trigger_settings = %{
      type: "metric_signal",
      metric: "active_addresses_24h",
      target: %{slug: "santiment"},
      channel: %{"webhook_url" => "not_a_url"},
      time_window: "1d",
      operation: %{percent_up: 300.0},
      triggered?: false,
      payload: nil
    }

    capture_log(fn ->
      {:error, error_msg} =
        UserTrigger.create_user_trigger(user, %{
          title: "Generic title",
          is_public: true,
          settings: trigger_settings
        })

      assert error_msg =~ "Trigger structure is invalid. Key `settings` is not valid. "

      assert error_msg =~
               "Reason: [\"%{webhook_url: \\\"not_a_url\\\"} is not a valid notification channel. The available notification channels are [telegram_channel, telegram, email, web_push, webhook]\\n\"]"
    end)
  end

  test "try creating user trigger with unknown channel" do
    user = insert(:user)

    trigger_settings = %{
      type: "metric_signal",
      metric: "active_addresses_24h",
      target: %{slug: "santiment"},
      channel: "unknown",
      time_window: "1d",
      operation: %{percent_up: 300.0},
      triggered?: false,
      payload: nil
    }

    error_log =
      capture_log(fn ->
        {:error, error_msg} =
          UserTrigger.create_user_trigger(user, %{
            title: "Generic title",
            is_public: true,
            settings: trigger_settings
          })

        assert error_msg =~ "Trigger structure is invalid. Key `settings` is not valid. "

        assert error_msg =~
                 ~s/Reason: [\"\\\"unknown\\\" is not a valid notification channel. The available notification channels are [telegram_channel, telegram, email, web_push, webhook]\\n\"]/
      end)

    assert error_log =~
             "UserTrigger struct is not valid."

    assert error_log =~
             ~s/Reason: [\"\\\"unknown\\\" is not a valid notification channel. The available notification channels are [telegram_channel, telegram, email, web_push, webhook]\\n\"]/
  end

  test "try creating user trigger with required field in struct" do
    user = insert(:user)

    settings = %{
      type: "metric_signal",
      metric: "active_addresses_24h",
      target: %{slug: "santiment"},
      time_window: "1d",
      operation: %{percent_up: 300.0}
    }

    assert capture_log(fn ->
             {:error, error_msg} =
               UserTrigger.create_user_trigger(user, %{
                 title: "Generic title",
                 is_public: true,
                 settings: settings
               })

             assert error_msg =~ "Trigger structure is invalid. Key `settings` is not valid."

             assert error_msg =~
                      ~s/Reason: ["nil is not a valid notification channel. The available notification channels are [telegram_channel, telegram, email, web_push, webhook]\\n\"]/
           end) =~ "UserTrigger struct is not valid"
  end

  test "create user trigger with optional field missing" do
    user = insert(:user)

    trigger_settings = %{
      type: "metric_signal",
      metric: "price_usd",
      target: %{slug: "santiment"},
      operation: %{percent_up: 20},
      channel: "telegram",
      time_window: "1d"
    }

    title = "Some title"

    {:ok, created_trigger} =
      UserTrigger.create_user_trigger(user, %{
        title: title,
        is_public: true,
        settings: trigger_settings
      })

    assert trigger_settings.target == created_trigger.trigger.settings |> Map.get(:target)
    assert title == created_trigger.trigger.title
  end

  test "create trigger with icon and description" do
    user = insert(:user)

    trigger_settings = %{
      type: "metric_signal",
      metric: "price_usd",
      target: %{slug: "santiment"},
      operation: %{percent_up: 20},
      channel: "telegram",
      time_window: "1d"
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
    assert title == created_trigger.trigger.title
    assert description == created_trigger.trigger.description
    assert icon_url == created_trigger.trigger.icon_url
  end

  test "create trigger when there is existing one" do
    user = insert(:user)

    trigger_settings1 = %{
      type: "metric_signal",
      metric: "active_addresses_24h",
      target: %{slug: "santiment"},
      channel: "telegram",
      time_window: "1d",
      operation: %{percent_down: 300.0}
    }

    insert(:user_trigger,
      user: user,
      trigger: %{title: "Generic title", is_public: true, settings: trigger_settings1}
    )

    assert length(UserTrigger.triggers_for(user.id)) == 1

    trigger_settings2 = %{
      type: "metric_signal",
      metric: "price_usd",
      target: %{slug: "santiment"},
      channel: "email",
      time_window: "1d",
      operation: %{percent_down: 250.0}
    }

    {:ok, _} =
      UserTrigger.create_user_trigger(user, %{
        title: "Generic title",
        is_public: true,
        settings: trigger_settings2
      })

    assert length(UserTrigger.triggers_for(user.id)) == 2
  end

  test "update trigger" do
    user = insert(:user)

    trigger_settings1 = %{
      type: "metric_signal",
      metric: "active_addresses_24h",
      target: %{slug: "santiment"},
      channel: "telegram",
      time_window: "1d",
      operation: %{percent_up: 300.0}
    }

    trigger_settings2 = %{
      type: "metric_signal",
      metric: "price_usd",
      target: %{slug: "santiment"},
      channel: "email",
      time_window: "1d",
      operation: %{percent_up: 10.0}
    }

    insert(:user_trigger,
      user: user,
      trigger: %{title: "Generic title", is_public: true, settings: trigger_settings1}
    )

    insert(:user_trigger,
      user: user,
      trigger: %{title: "Generic title2", is_public: true, settings: trigger_settings2}
    )

    trigger_id = UserTrigger.triggers_for(user.id) |> hd |> Map.get(:id)

    updated_trigger = %{
      type: "metric_signal",
      metric: "active_addresses_24h",
      target: %{slug: "santiment"},
      channel: "telegram",
      time_window: "1d",
      operation: %{percent_up: 200.0}
    }

    new_title = "New title"
    new_description = "New description"

    new_icon_url =
      "http://stage-sanbase-images.s3.amazonaws.com/uploads/_empowr-coinHY5QG72SCGKYWMN4AEJQ2BRDLXNWXECT.png"

    {:ok, _} =
      UserTrigger.update_user_trigger(user.id, %{
        id: trigger_id,
        settings: updated_trigger,
        is_public: false,
        title: new_title,
        description: new_description,
        icon_url: new_icon_url
      })

    triggers = UserTrigger.triggers_for(user.id)

    assert length(triggers) == 2

    %UserTrigger{trigger: trigger} =
      Enum.find(triggers, fn %UserTrigger{id: id} -> id == trigger_id end)

    assert trigger.title == new_title
    assert trigger.description == new_description
    assert trigger.icon_url == new_icon_url
  end

  test "update only common fields" do
    user = insert(:user)

    trigger_settings = %{
      type: "metric_signal",
      metric: "active_addresses_24h",
      target: %{slug: "santiment"},
      channel: "telegram",
      time_window: "1d",
      operation: %{percent_up: 200.0}
    }

    insert(:user_trigger,
      user: user,
      trigger: %{title: "Generic title", is_public: false, settings: trigger_settings}
    )

    ut = UserTrigger.triggers_for(user.id)
    trigger_id = ut |> hd |> Map.get(:id)

    UserTrigger.update_user_trigger(user.id, %{id: trigger_id, is_public: true, cooldown: "1h"})
    user_triggers = UserTrigger.triggers_for(user.id)
    assert length(user_triggers) == 1
    trigger = user_triggers |> hd()
    assert trigger.trigger.is_public == true
    assert trigger.trigger.cooldown == "1h"
  end

  @tag capture_log: true
  test "too big time_window is not valid" do
    user = insert(:user)

    trigger_settings = %{
      type: "metric_signal",
      metric: "active_addresses_24h",
      target: %{slug: "santiment"},
      channel: "telegram",
      time_window: "250000000000m",
      operation: %{percent_up: 200.0}
    }

    assert {:error, error_msg} =
             UserTrigger.create_user_trigger(user, %{
               title: "Generic title",
               is_public: true,
               cooldown: "1d",
               settings: trigger_settings
             })

    assert error_msg =~ "The time_window parameter must not be bigger than 1 year"
    assert error_msg =~ "Provided value: #{trigger_settings.time_window}"
  end
end
