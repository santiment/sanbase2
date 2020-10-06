defmodule Sanbase.Signal.DailyActiveAddressesPercentUpChangeTest do
  use Sanbase.DataCase, async: false

  import Mock
  import Sanbase.Factory
  import Sanbase.TestHelpers

  alias Sanbase.Signal.UserTrigger
  alias Sanbase.Signal.Evaluator

  alias Sanbase.Signal.Trigger.DailyActiveAddressesSettings

  setup do
    Sanbase.Signal.Evaluator.Cache.clear_all()

    user = insert(:user, user_settings: %{settings: %{signal_notify_telegram: true}})
    Sanbase.Auth.UserSettings.set_telegram_chat_id(user.id, 123_123_123_123)

    project = insert(:random_erc20_project)

    trigger_settings1 = %{
      type: "daily_active_addresses",
      target: %{slug: project.slug},
      channel: "telegram",
      time_window: "7d",
      operation: %{percent_up: 300.0}
    }

    trigger_settings2 = %{
      type: "daily_active_addresses",
      target: %{slug: project.slug},
      channel: "telegram",
      time_window: "7d",
      operation: %{percent_up: 200.0}
    }

    {:ok, trigger1} =
      UserTrigger.create_user_trigger(user, %{
        title: "Generic title",
        is_public: true,
        cooldown: "12h",
        settings: trigger_settings1
      })

    {:ok, trigger2} =
      UserTrigger.create_user_trigger(user, %{
        title: "Generic title",
        is_public: true,
        cooldown: "1d",
        settings: trigger_settings2
      })

    datetimes = generate_datetimes(~U[2019-01-01 00:00:00Z], "1d", 7)

    [
      user: user,
      project: project,
      trigger1: trigger1,
      trigger2: trigger2,
      datetimes: datetimes
    ]
  end

  test "all of daily active addresses signals triggered", context do
    data =
      Enum.zip(context.datetimes, [100, 100, 100, 100, 100, 100, 5000])
      |> Enum.map(&%{datetime: elem(&1, 0), value: elem(&1, 1)})

    with_mock DailyActiveAddressesSettings, [:passthrough],
      get_data: fn _ ->
        [{context.project.slug, data}]
      end do
      [triggered1, triggered2 | rest] =
        DailyActiveAddressesSettings.type()
        |> UserTrigger.get_active_triggers_by_type()
        |> Evaluator.run()

      # 2 signals triggered
      assert rest == []
      triggered_ids = [triggered1.id, triggered2.id] |> Enum.sort()
      expected_ids = [context.trigger1.id, context.trigger2.id] |> Enum.sort()

      assert triggered_ids == expected_ids
    end
  end

  test "only some of daily active addresses signals triggered", context do
    data =
      Enum.zip(context.datetimes, [100, 120, 100, 80, 200, 200, 600])
      |> Enum.map(&%{datetime: elem(&1, 0), value: elem(&1, 1)})

    with_mock DailyActiveAddressesSettings, [:passthrough],
      get_data: fn _ ->
        [{context.project.slug, data}]
      end do
      [triggered | rest] =
        DailyActiveAddressesSettings.type()
        |> UserTrigger.get_active_triggers_by_type()
        |> Evaluator.run()

      # 1 signal triggered
      assert rest == []
      assert context.trigger2.id == triggered.id
    end
  end

  test "none of daily active addresses signals triggered", context do
    data =
      Enum.zip(context.datetimes, [100, 100, 100, 100, 100, 100, 100])
      |> Enum.map(&%{datetime: elem(&1, 0), value: elem(&1, 1)})

    with_mock DailyActiveAddressesSettings, [:passthrough],
      get_data: fn _ ->
        [{context.project.slug, data}]
      end do
      triggered =
        DailyActiveAddressesSettings.type()
        |> UserTrigger.get_active_triggers_by_type()
        |> Evaluator.run()

      # 0 signals triggered
      assert triggered == []
    end
  end

  # We had the problem where the whole trigger struct was taken from the cache,
  # meaning everything including the id and title were overriden
  test "only payload and triggered are taken from cache", context do
    data =
      Enum.zip(context.datetimes, [100, 120, 100, 80, 100, 100, 500])
      |> Enum.map(&%{datetime: elem(&1, 0), value: elem(&1, 1)})

    with_mock DailyActiveAddressesSettings, [:passthrough],
      get_data: fn _ ->
        [{context.project.slug, data}]
      end do
      trigger_settings1 = %{
        type: "daily_active_addresses",
        target: %{slug: context.project.slug},
        channel: "telegram",
        time_window: "1d",
        operation: %{percent_up: 100.0}
      }

      {:ok, trigger1} =
        UserTrigger.create_user_trigger(context.user, %{
          title: "Generic title1",
          is_public: true,
          cooldown: "12h",
          settings: trigger_settings1
        })

      {:ok, trigger2} =
        UserTrigger.create_user_trigger(context.user, %{
          title: "Generic title2",
          is_public: true,
          cooldown: "12h",
          settings: trigger_settings1
        })

      type = DailyActiveAddressesSettings.type()

      [triggered1, triggered2] =
        type
        |> UserTrigger.get_active_triggers_by_type()
        |> Enum.filter(fn %{id: id} -> id in [trigger1.id, trigger2.id] end)
        |> Sanbase.Signal.Evaluator.run(type)

      # Assert that not the whole trigger is replaced when it's taken from cache
      # but only `payload` and the `triggered?`
      assert triggered1.trigger.settings.payload == triggered2.trigger.settings.payload
      assert triggered1.trigger.settings.triggered? == triggered2.trigger.settings.triggered?
      refute triggered1.trigger.title == triggered2.trigger.title
      refute triggered1.trigger.id == triggered2.trigger.id
    end
  end

  test "last_triggered is taken into account for the cache key - different last_triggered",
       context do
    data =
      Enum.zip(context.datetimes, [100, 120, 100, 80, 20, 10, 5])
      |> Enum.map(&%{datetime: elem(&1, 0), value: elem(&1, 1)})

    with_mock DailyActiveAddressesSettings, [:passthrough],
      get_data: fn _ ->
        [{context.project.slug, data}]
      end do
      trigger_settings1 = %{
        type: "daily_active_addresses",
        target: %{slug: context.project.slug},
        channel: "telegram",
        time_window: "1d",
        operation: %{percent_up: 100.0}
      }

      {:ok, trigger1} =
        UserTrigger.create_user_trigger(context.user, %{
          title: "Generic title1",
          is_public: true,
          cooldown: "12h",
          settings: trigger_settings1
        })

      UserTrigger.update_user_trigger(context.user, %{
        id: trigger1.id,
        last_triggered: %{}
      })

      {:ok, trigger2} =
        UserTrigger.create_user_trigger(context.user, %{
          title: "Generic title2",
          is_public: true,
          cooldown: "12h",
          settings: %{trigger_settings1 | channel: "email"}
        })

      UserTrigger.update_user_trigger(context.user, %{
        id: trigger2.id,
        last_triggered: %{context.project.slug => Timex.shift(Timex.now(), days: -2)}
      })

      type = DailyActiveAddressesSettings.type()

      type
      |> UserTrigger.get_active_triggers_by_type()
      |> Enum.filter(fn %{id: id} -> id in [trigger1.id, trigger2.id] end)
      |> Sanbase.Signal.Evaluator.run(type)

      assert_called(DailyActiveAddressesSettings.get_data(%{channel: "email"}))
      assert_called(DailyActiveAddressesSettings.get_data(%{channel: "telegram"}))
    end
  end

  test "last_triggered is taken into account for the cache key - same last_triggered",
       context do
    data =
      Enum.zip(context.datetimes, [100, 120, 100, 80, 20, 10, 5])
      |> Enum.map(&%{datetime: elem(&1, 0), value: elem(&1, 1)})

    with_mock DailyActiveAddressesSettings, [:passthrough],
      get_data: fn _ ->
        [{context.project.slug, data}]
      end do
      trigger_settings1 = %{
        type: "daily_active_addresses",
        target: %{slug: context.project.slug},
        channel: "telegram",
        time_window: "1d",
        operation: %{percent_up: 100.0}
      }

      {:ok, trigger1} =
        UserTrigger.create_user_trigger(context.user, %{
          title: "Generic title1",
          is_public: true,
          cooldown: "12h",
          settings: trigger_settings1
        })

      UserTrigger.update_user_trigger(context.user, %{
        id: trigger1.id,
        last_triggered: %{}
      })

      {:ok, trigger2} =
        UserTrigger.create_user_trigger(context.user, %{
          title: "Generic title2",
          is_public: true,
          cooldown: "12h",
          settings: %{trigger_settings1 | channel: "email"}
        })

      UserTrigger.update_user_trigger(context.user, %{
        id: trigger2.id,
        last_triggered: %{}
      })

      type = DailyActiveAddressesSettings.type()

      type
      |> UserTrigger.get_active_triggers_by_type()
      |> Enum.filter(fn %{id: id} -> id in [trigger1.id, trigger2.id] end)
      |> Sanbase.Signal.Evaluator.run(type)

      # Only one of the signals called `get_data`, the other fetched the data
      # from the cache
      email_called? =
        try do
          assert_called(DailyActiveAddressesSettings.get_data(%{channel: "email"}))
          true
        rescue
          _ -> false
        end

      telegram_called? =
        try do
          assert_called(DailyActiveAddressesSettings.get_data(%{channel: "telegram"}))
          true
        rescue
          _ -> false
        end

      assert [email_called?, telegram_called?] |> Enum.sort() == [false, true]
    end
  end
end
