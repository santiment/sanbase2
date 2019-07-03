defmodule Sanbase.Signal.EvaluatorTest do
  use Sanbase.DataCase, async: false

  import Mock
  import Sanbase.Factory
  import ExUnit.CaptureLog

  alias Sanbase.Signal.{UserTrigger, HistoricalActivity}
  alias Sanbase.Signal.Evaluator

  alias Sanbase.Signal.Trigger.DailyActiveAddressesSettings

  setup_with_mocks([
    {Sanbase.Chart, [],
     [
       build_embedded_chart: fn _, _, _, _ -> [%{image: %{url: "somelink"}}] end,
       build_embedded_chart: fn _, _, _ -> [%{image: %{url: "somelink"}}] end
     ]}
  ]) do
    Sanbase.Signal.Evaluator.Cache.clear()

    user = insert(:user)
    Sanbase.Auth.UserSettings.set_telegram_chat_id(user.id, 123_123_123_123)

    Sanbase.Factory.insert(:project, %{
      name: "Santiment",
      ticker: "SAN",
      coinmarketcap_id: "santiment",
      main_contract_address: "0x7c5a0ce9267ed19b22f8cae653f198e3e8daf098"
    })

    trigger_settings1 = %{
      type: "daily_active_addresses",
      target: %{slug: "santiment"},
      channel: "telegram",
      time_window: "1d",
      percent_threshold: 300.0
    }

    trigger_settings2 = %{
      type: "daily_active_addresses",
      target: %{slug: "santiment"},
      channel: "telegram",
      time_window: "1d",
      percent_threshold: 200.0
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

    [
      user: user,
      trigger1: trigger1,
      trigger2: trigger2
    ]
  end

  test "all of daily active addresses signals triggered", context do
    with_mock DailyActiveAddressesSettings, [:passthrough],
      get_data: fn _ ->
        [{"santiment", {100, 20}}]
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
    with_mock DailyActiveAddressesSettings, [:passthrough],
      get_data: fn _ ->
        [{"santiment", {100, 30}}]
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

  test "none of daily active addresses signals triggered", _context do
    with_mock DailyActiveAddressesSettings, [:passthrough],
      get_data: fn _ ->
        [{"santiment", {100, 100}}]
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
    with_mock DailyActiveAddressesSettings, [:passthrough],
      get_data: fn _ ->
        [{"santiment", {100, 30}}]
      end do
      trigger_settings1 = %{
        type: "daily_active_addresses",
        target: %{slug: "santiment"},
        channel: "telegram",
        time_window: "1d",
        percent_threshold: 100.0
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
    with_mock DailyActiveAddressesSettings, [:passthrough],
      get_data: fn _ ->
        [{"santiment", {100, 30}}]
      end do
      trigger_settings1 = %{
        type: "daily_active_addresses",
        target: %{slug: "santiment"},
        channel: "telegram",
        time_window: "1d",
        percent_threshold: 100.0
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
        last_triggered: %{"santiment" => Timex.shift(Timex.now(), days: -2)}
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
    with_mock DailyActiveAddressesSettings, [:passthrough],
      get_data: fn _ ->
        [{"santiment", {100, 30}}]
      end do
      trigger_settings1 = %{
        type: "daily_active_addresses",
        target: %{slug: "santiment"},
        channel: "telegram",
        time_window: "1d",
        percent_threshold: 100.0
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
