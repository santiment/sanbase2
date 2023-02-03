defmodule Sanbase.Alert.WalletTriggerTest do
  use Sanbase.DataCase, async: false

  import Mock
  import Sanbase.Factory
  import ExUnit.CaptureLog

  alias Sanbase.Alert.{
    UserTrigger,
    Trigger.WalletTriggerSettings,
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

    project =
      Sanbase.Factory.insert(:random_erc20_project,
        eth_addresses: [
          build(:project_eth_address, address: "0x77Fd8239ECf7aBcEaF9F2c14F5aCAE950e7B3e98")
        ]
      )

    trigger_settings1 = %{
      type: "wallet_movement",
      selector: %{infrastructure: "ETH", slug: "ethereum"},
      target: %{slug: project.slug},
      channel: "telegram",
      time_window: "1d",
      operation: %{amount_up: 25.0}
    }

    trigger_settings2 = %{
      type: "wallet_movement",
      selector: %{infrastructure: "ETH", slug: "some-weird-token"},
      target: %{address: "0x77Fd8239ECf7aBcEaF9F2c14F5aCAE950e7B3e98"},
      channel: "telegram",
      time_window: "1d",
      operation: %{amount_up: 200.0}
    }

    trigger_settings3 = %{
      type: "wallet_movement",
      selector: %{infrastructure: "XRP", currency: "BTC"},
      target: %{address: "0x77Fd8239ECf7aBcEaF9F2c14F5aCAE950e7B3e98"},
      channel: "telegram",
      time_window: "1d",
      operation: %{amount_down: 50.0}
    }

    {:ok, _} =
      UserTrigger.create_user_trigger(user, %{
        title: "Generic title",
        is_public: true,
        cooldown: "12h",
        settings: trigger_settings1
      })

    {:ok, _} =
      UserTrigger.create_user_trigger(user, %{
        title: "Generic title",
        is_public: true,
        cooldown: "1d",
        settings: trigger_settings2
      })

    {:ok, _} =
      UserTrigger.create_user_trigger(user, %{
        title: "Generic title",
        is_public: true,
        cooldown: "1d",
        settings: trigger_settings3
      })

    [
      project: project,
      address: address
    ]
  end

  test "signal setting cooldown works for wallet movement", context do
    with_mocks [
      {Sanbase.Telegram, [:passthrough], send_message: fn _user, _text -> :ok end},
      {HistoricalBalance, [:passthrough],
       balance_change: fn _, _, _, _ ->
         {:ok,
          [
            %{
              address: Sanbase.BlockchainAddress.to_internal_format(context.address),
              balance_start: 20,
              balance_end: 300,
              balance_change_amount: 280,
              balance_change_percent: 1400.0
            }
          ]}
       end}
    ] do
      assert capture_log(fn -> Scheduler.run_alert(WalletTriggerSettings) end) =~
               "In total 2/2 wallet_movement alerts were sent successfully"

      Sanbase.Cache.clear_all(:alerts_evaluator_cache)

      assert capture_log(fn -> Scheduler.run_alert(WalletTriggerSettings) end) =~
               "There were no wallet_movement alerts triggered"
    end
  end

  test "triggers eth wallet signal when balance increases", context do
    test_pid = self()

    with_mocks [
      {Sanbase.Telegram, [:passthrough],
       send_message: fn _user, text ->
         send(test_pid, {:telegram_to_self, text})
         :ok
       end},
      {HistoricalBalance, [:passthrough],
       balance_change: fn _, _, _, _ ->
         {:ok,
          [
            %{
              address: Sanbase.BlockchainAddress.to_internal_format(context.address),
              balance_start: 20,
              balance_end: 70,
              balance_change_amount: 50,
              balance_change_percent: 250.0
            }
          ]}
       end}
    ] do
      Scheduler.run_alert(WalletTriggerSettings)

      assert_receive({:telegram_to_self, message})

      assert message =~
               "**#{context.project.name}**'s ethereum balance on the Ethereum blockchain has increased by 50"

      assert message =~ "Was: 20\nNow: 70"
    end
  end

  test "triggers eth wallet and address alerts when balance increases", context do
    test_pid = self()

    with_mocks [
      {Sanbase.Telegram, [:passthrough],
       send_message: fn _user, text ->
         send(test_pid, {:telegram_to_self, text})
         :ok
       end},
      {HistoricalBalance, [:passthrough],
       balance_change: fn _, _, _, _ ->
         {:ok,
          [
            %{
              address: Sanbase.BlockchainAddress.to_internal_format(context.address),
              balance_start: 20,
              balance_end: 300,
              balance_change_amount: 280,
              balance_change_percent: 1400.0
            }
          ]}
       end}
    ] do
      Scheduler.run_alert(WalletTriggerSettings)

      assert_receive({:telegram_to_self, message1})
      assert_receive({:telegram_to_self, message2})

      # Plain sort won't work as depends on the randomly generated project name
      # Sorting on wheter there is `address` substring is deterministic
      sorted_messages = Enum.sort_by([message1, message2], &String.contains?(&1, "address"))

      assert Enum.at(sorted_messages, 0) =~
               "**#{context.project.name}**'s ethereum balance on the Ethereum blockchain has increased by 280"

      assert Enum.at(sorted_messages, 0) =~ "Was: 20\nNow: 300"

      assert Enum.at(sorted_messages, 1) =~
               "The address #{context.address}'s some-weird-token balance on the Ethereum blockchain has increased by 280."

      assert Enum.at(sorted_messages, 1) =~ "Was: 20\nNow: 300"
    end
  end

  test "triggers address signal when balance decreases", context do
    test_pid = self()

    with_mocks [
      {Sanbase.Telegram, [:passthrough],
       send_message: fn _user, text ->
         send(test_pid, {:telegram_to_self, text})
         :ok
       end},
      {HistoricalBalance, [:passthrough],
       balance_change: fn _, _, _, _ ->
         {:ok,
          [
            %{
              address: Sanbase.BlockchainAddress.to_internal_format(context.address),
              balance_start: 100,
              balance_end: 0,
              balance_change_amount: -100,
              balance_change_percent: -100.0
            }
          ]}
       end}
    ] do
      Scheduler.run_alert(WalletTriggerSettings)

      assert_receive({:telegram_to_self, message})

      assert message =~
               "The address #{context.address}'s BTC balance on the XRP Ledger blockchain has decreased by 100"

      assert message =~ "Was: 100\nNow: 0"
    end
  end

  test "behavior is correct in case of database error" do
    test_pid = self()

    with_mocks [
      {Sanbase.Telegram, [:passthrough],
       send_message: fn _user, text ->
         send(test_pid, {:telegram_to_self, text})
         :ok
       end},
      {HistoricalBalance, [:passthrough],
       balance_change: fn _, _, _, _ ->
         {:error, "Something bad happened"}
       end}
    ] do
      Scheduler.run_alert(WalletTriggerSettings)

      refute_receive({:telegram_to_self, _})
    end
  end
end
