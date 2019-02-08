defmodule Sanbase.Signals.EvaluatorTest do
  use Sanbase.DataCase, async: false

  import Mock
  import Sanbase.Factory
  import ExUnit.CaptureLog

  alias Sanbase.Signals.UserTrigger
  alias Sanbase.Signals.Evaluator
  alias Sanbase.Signals.Trigger.DailyActiveAddressesSettings

  setup_with_mocks([
    {Sanbase.Chart, [],
     [
       build_embedded_chart: fn _, _, _, _ -> [%{image: %{url: "somelink"}}] end,
       build_embedded_chart: fn _, _, _ -> [%{image: %{url: "somelink"}}] end
     ]}
  ]) do
    Sanbase.Signals.Evaluator.Cache.clear()

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
        cooldown: "12h",
        settings: trigger_settings1
      })

    {:ok, trigger2} =
      UserTrigger.create_user_trigger(user, %{
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

  test "evaluate triggers all criteria match", context do
    with_mock DailyActiveAddressesSettings, [:passthrough],
      get_data: fn _ ->
        {100, 20}
      end do
      [triggered1, triggered2 | rest] =
        DailyActiveAddressesSettings.type()
        |> UserTrigger.get_triggers_by_type()
        |> Evaluator.run()

      # 2 signals triggered
      assert length(rest) == 0
      assert context.trigger1.id == triggered1.id
      assert context.trigger2.id == triggered2.id
    end
  end

  test "setting cooldown works", context do
    with_mock DailyActiveAddressesSettings, [:passthrough],
      get_data: fn _ ->
        {100, 30}
      end do
      Tesla.Mock.mock_global(fn
        %{method: :post} ->
          %Tesla.Env{status: 200, body: "ok"}
      end)

      Logger.configure(level: :info)

      assert capture_log(fn ->
               Sanbase.Signals.Scheduler.run_daily_active_addresses_signals()
             end) =~ "signals were sent successfully"

      assert capture_log(fn ->
               Sanbase.Signals.Scheduler.run_daily_active_addresses_signals()
             end) =~ "There were no signals triggered of type"
    end
  end

  test "evaluate triggers some criteria match", context do
    with_mock DailyActiveAddressesSettings, [:passthrough],
      get_data: fn _ ->
        {100, 30}
      end do
      [triggered | rest] =
        DailyActiveAddressesSettings.type()
        |> UserTrigger.get_triggers_by_type()
        |> Evaluator.run()

      # 1 signal triggered
      assert length(rest) == 0
      assert context.trigger2.id == triggered.id
    end
  end

  test "evaluate triggers no criteria match", _context do
    with_mock DailyActiveAddressesSettings, [:passthrough],
      get_data: fn _ ->
        {100, 100}
      end do
      triggered =
        DailyActiveAddressesSettings.type()
        |> UserTrigger.get_triggers_by_type()
        |> Evaluator.run()

      # 0 signals triggered
      assert length(triggered) == 0
    end
  end

  # Private functions
end
