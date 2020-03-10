defmodule Sanbase.Signal.DailyActiveAddresseAbsoluetChangeTest do
  use Sanbase.DataCase, async: false

  import Mock
  import Sanbase.Factory
  import Sanbase.TestHelpers
  alias Sanbase.Signal.UserTrigger
  alias Sanbase.Signal.Evaluator

  alias Sanbase.Signal.Trigger.DailyActiveAddressesSettings

  setup_with_mocks([
    {Sanbase.GoogleChart, [],
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
      slug: "santiment",
      main_contract_address: "0x7c5a0ce9267ed19b22f8cae653f198e3e8daf098"
    })

    trigger_settings1 = %{
      type: "daily_active_addresses",
      target: %{slug: "santiment"},
      channel: "telegram",
      operation: %{above: 300}
    }

    trigger_settings2 = %{
      type: "daily_active_addresses",
      target: %{slug: "santiment"},
      channel: "telegram",
      operation: %{below: 30}
    }

    trigger_settings3 = %{
      type: "daily_active_addresses",
      target: %{slug: "santiment"},
      channel: "telegram",
      operation: %{outside_channel: [1, 1000]}
    }

    trigger_settings4 = %{
      type: "daily_active_addresses",
      target: %{slug: "santiment"},
      channel: "telegram",
      operation: %{inside_channel: [500, 1000]}
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

    {:ok, trigger3} =
      UserTrigger.create_user_trigger(user, %{
        title: "Generic title",
        is_public: true,
        cooldown: "1d",
        settings: trigger_settings3
      })

    {:ok, trigger4} =
      UserTrigger.create_user_trigger(user, %{
        title: "Generic title",
        is_public: true,
        cooldown: "1d",
        settings: trigger_settings4
      })

    datetimes = generate_datetimes(~U[2019-01-01 00:00:00Z], "1d", 7)

    [
      user: user,
      trigger1: trigger1,
      trigger2: trigger2,
      trigger3: trigger3,
      trigger4: trigger4,
      datetimes: datetimes
    ]
  end

  test "DAA value 5000", context do
    data =
      Enum.zip(context.datetimes, [100, 100, 100, 100, 100, 100, 5000])
      |> Enum.map(&%{datetime: elem(&1, 0), active_addresses: elem(&1, 1)})

    with_mock DailyActiveAddressesSettings, [:passthrough],
      get_data: fn _ ->
        [{"santiment", data}]
      end do
      [triggered1, triggered2 | rest] =
        DailyActiveAddressesSettings.type()
        |> UserTrigger.get_active_triggers_by_type()
        |> Evaluator.run()

      # 2 signals triggered
      assert rest == []
      triggered_ids = [triggered1.id, triggered2.id] |> Enum.sort()
      expected_ids = [context.trigger1.id, context.trigger3.id] |> Enum.sort()

      assert triggered_ids == expected_ids
    end
  end

  test "Daa value 400", context do
    data =
      Enum.zip(context.datetimes, [100, 120, 100, 80, 200, 200, 400])
      |> Enum.map(&%{datetime: elem(&1, 0), active_addresses: elem(&1, 1)})

    with_mock DailyActiveAddressesSettings, [:passthrough],
      get_data: fn _ ->
        [{"santiment", data}]
      end do
      [triggered | rest] =
        DailyActiveAddressesSettings.type()
        |> UserTrigger.get_active_triggers_by_type()
        |> Evaluator.run()

      # 1 signal triggered
      assert rest == []
      assert context.trigger1.id == triggered.id
    end
  end

  test "DAA value 10", context do
    data =
      Enum.zip(context.datetimes, [100, 100, 100, 100, 100, 100, 10])
      |> Enum.map(&%{datetime: elem(&1, 0), active_addresses: elem(&1, 1)})

    with_mock DailyActiveAddressesSettings, [:passthrough],
      get_data: fn _ ->
        [{"santiment", data}]
      end do
      [triggered] =
        DailyActiveAddressesSettings.type()
        |> UserTrigger.get_active_triggers_by_type()
        |> Evaluator.run()

      # 0 signals triggered
      assert triggered.id == context.trigger2.id
    end
  end

  # We had the problem where the whole trigger struct was taken from the cache,
  # meaning everything including the id and title were overriden
  test "DAA value 0", context do
    data =
      Enum.zip(context.datetimes, [100, 120, 100, 80, 100, 100, 0])
      |> Enum.map(&%{datetime: elem(&1, 0), active_addresses: elem(&1, 1)})

    with_mock DailyActiveAddressesSettings, [:passthrough],
      get_data: fn _ ->
        [{"santiment", data}]
      end do
      [triggered1, triggered2 | rest] =
        DailyActiveAddressesSettings.type()
        |> UserTrigger.get_active_triggers_by_type()
        |> Evaluator.run()

      # 2 signals triggered
      assert rest == []
      triggered_ids = [triggered1.id, triggered2.id] |> Enum.sort()
      expected_ids = [context.trigger2.id, context.trigger3.id] |> Enum.sort()

      assert triggered_ids == expected_ids
    end
  end

  test "DAA value 700", context do
    data =
      Enum.zip(context.datetimes, [100, 120, 100, 80, 100, 100, 700])
      |> Enum.map(&%{datetime: elem(&1, 0), active_addresses: elem(&1, 1)})

    with_mock DailyActiveAddressesSettings, [:passthrough],
      get_data: fn _ ->
        [{"santiment", data}]
      end do
      [triggered1, triggered2 | rest] =
        DailyActiveAddressesSettings.type()
        |> UserTrigger.get_active_triggers_by_type()
        |> Evaluator.run()

      # 2 signals triggered
      assert rest == []
      triggered_ids = [triggered1.id, triggered2.id] |> Enum.sort()
      expected_ids = [context.trigger1.id, context.trigger4.id] |> Enum.sort()

      assert triggered_ids == expected_ids
    end
  end

  test "last_triggered is taken into account for the cache key - different last_triggered",
       context do
    data =
      Enum.zip(context.datetimes, [100, 120, 100, 80, 20, 10, 5])
      |> Enum.map(&%{datetime: elem(&1, 0), active_addresses: elem(&1, 1)})

    with_mock DailyActiveAddressesSettings, [:passthrough],
      get_data: fn _ ->
        [{"santiment", data}]
      end do
      trigger_settings1 = %{
        type: "daily_active_addresses",
        target: %{slug: "santiment"},
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
    data =
      Enum.zip(context.datetimes, [100, 120, 100, 80, 20, 10, 5])
      |> Enum.map(&%{datetime: elem(&1, 0), active_addresses: elem(&1, 1)})

    with_mock DailyActiveAddressesSettings, [:passthrough],
      get_data: fn _ ->
        [{"santiment", data}]
      end do
      trigger_settings1 = %{
        type: "daily_active_addresses",
        target: %{slug: "santiment"},
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
