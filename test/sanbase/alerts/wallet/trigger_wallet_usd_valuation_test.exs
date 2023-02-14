defmodule Sanbase.Alert.WalletUsdValuationTriggerSettingsTest do
  use Sanbase.DataCase, async: false

  import Mock
  import Sanbase.Factory
  import ExUnit.CaptureLog

  alias Sanbase.Alert.{
    UserTrigger,
    Trigger.WalletUsdValuationTriggerSettings,
    Scheduler
  }

  alias Sanbase.Clickhouse.HistoricalBalance

  setup do
    Sanbase.Cache.clear_all(:alerts_evaluator_cache)

    user = insert(:user, user_settings: %{settings: %{alert_notify_telegram: true}})
    Sanbase.Accounts.UserSettings.set_telegram_chat_id(user.id, 123_123_123_123)

    # Provide this mixed case (both lower and upper case letters) to the trigger settings
    # to test the behavior of transform to some internal format.
    address = "0x77Fd8239ECf7aBcEaF9F2c14F5aCAE950e7B3e98"

    base_settings = %{
      type: "wallet_usd_valuation",
      selector: %{infrastructure: "ETH"},
      target: %{address: address},
      channel: "telegram",
      time_window: "1d"
    }

    settings1 = Map.put(base_settings, :operation, %{amount_down: 100_000_000})
    settings2 = Map.put(base_settings, :operation, %{percent_down: 5})
    settings3 = Map.put(base_settings, :operation, %{percent_up: 10})

    for settings <- [settings1, settings2, settings3] do
      {:ok, _} =
        UserTrigger.create_user_trigger(
          user,
          %{title: "title", is_public: true, cooldown: "1d", settings: settings}
        )
    end

    %{address: address}
  end

  test "cooldown works for wallet_usd_valuation", _context do
    with_mocks [
      {Sanbase.Telegram, [:passthrough], send_message: fn _user, _text -> {:ok, "OK"} end},
      {HistoricalBalance, [:passthrough], usd_value_address_change: fn _, _ -> {:ok, data()} end}
    ] do
      log = capture_log(fn -> Scheduler.run_alert(WalletUsdValuationTriggerSettings) end)
      assert log =~ "In total 2/2 wallet_usd_valuation alerts were sent successfully"

      Sanbase.Cache.clear_all(:alerts_evaluator_cache)

      assert capture_log(fn -> Scheduler.run_alert(WalletUsdValuationTriggerSettings) end) =~
               "There were no wallet_usd_valuation alerts triggered"
    end
  end

  test "some alerts trigger", context do
    test_pid = self()

    with_mocks [
      {Sanbase.Telegram, [:passthrough],
       send_message: fn _user, text ->
         send(test_pid, {:telegram_to_self, text})
         {:ok, "OK"}
       end},
      {HistoricalBalance, [:passthrough], usd_value_address_change: fn _, _ -> {:ok, data()} end}
    ] do
      Scheduler.run_alert(WalletUsdValuationTriggerSettings)

      assert_receive({:telegram_to_self, message})

      assert message =~
               "The address #{context.address}'s total USD valuation has decreased by 177.70 Million"

      assert message =~ "Was: 2.07 Billion\nNow: 1.90 Billion"
    end
  end

  defp data() do
    [
      %{
        balance_change: -8.427353299921378,
        current_balance: 1_924_082.265599849,
        current_price_usd: 469.0361356389575,
        current_usd_value: 902_464_110.5084034,
        previous_balance: 1_924_073.838246549,
        previous_price_usd: 544.573324622657,
        previous_usd_value: 1_047_799_286.9133995,
        slug: "digixdao",
        usd_value_change: 145_335_176.40499604
      },
      %{
        balance_change: 0.0,
        current_balance: 14_600_299_531.569061,
        current_price_usd: 0.05163,
        current_usd_value: 753_813_464.8149107,
        previous_balance: 14_600_299_531.569061,
        previous_price_usd: 0.05306,
        previous_usd_value: 774_691_893.1450545,
        slug: "xinfin-network",
        usd_value_change: 20_878_428.33014381
      },
      %{
        balance_change: 0.0,
        current_balance: 16_030_443.377157,
        current_price_usd: 1.6967803881577543,
        current_usd_value: 27_200_141.935833357,
        previous_balance: 16_030_443.377157,
        previous_price_usd: 2.191165125475435,
        previous_usd_value: 35_125_348.473935075,
        slug: "polybius",
        usd_value_change: 7_925_206.538101718
      },
      %{
        balance_change: 0.0,
        current_balance: 75_000_002.05912834,
        current_price_usd: 0.9601,
        current_usd_value: 72_007_501.97696912,
        previous_balance: 75_000_002.05912834,
        previous_price_usd: 0.9967,
        previous_usd_value: 74_752_502.05233322,
        slug: "storj",
        usd_value_change: 2_745_000.075364098
      },
      %{
        balance_change: 0.0,
        current_balance: 500_000_057.10439026,
        current_price_usd: 0.28336596302872935,
        current_usd_value: 141_682_997.69580522,
        previous_balance: 500_000_057.10439026,
        previous_price_usd: 0.2850075749512946,
        previous_usd_value: 142_503_803.75083107,
        slug: "aleph-im",
        usd_value_change: 820_806.0550258458
      }
    ]
  end
end
