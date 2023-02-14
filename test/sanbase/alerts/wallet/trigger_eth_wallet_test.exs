defmodule Sanbase.Alert.EthWalletTriggerTest do
  use Sanbase.DataCase, async: false

  import Mock
  import Sanbase.Factory

  alias Sanbase.Project

  alias Sanbase.Alert.{
    UserTrigger,
    Trigger.EthWalletTriggerSettings,
    Scheduler
  }

  alias Sanbase.Clickhouse.HistoricalBalance

  setup do
    Sanbase.Cache.clear_all(:alerts_evaluator_cache)

    user = insert(:user, user_settings: %{settings: %{alert_notify_telegram: true}})
    Sanbase.Accounts.UserSettings.set_telegram_chat_id(user.id, 123_123_123_123)

    project = Sanbase.Factory.insert(:random_erc20_project)
    Sanbase.Factory.insert(%Project{name: "eth", slug: "ethereum"})

    {:ok, [eth_address]} = Project.eth_addresses(project)

    trigger_settings1 = %{
      type: "eth_wallet",
      target: %{slug: project.slug},
      asset: %{slug: "ethereum"},
      channel: "telegram",
      time_window: "1d",
      operation: %{amount_up: 25.0}
    }

    trigger_settings2 = %{
      type: "eth_wallet",
      target: %{eth_address: eth_address},
      asset: %{slug: "ethereum"},
      channel: "telegram",
      time_window: "1d",
      operation: %{amount_up: 200.0}
    }

    trigger_settings3 = %{
      type: "eth_wallet",
      target: %{eth_address: eth_address},
      asset: %{slug: "ethereum"},
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
      eth_address: eth_address
    ]
  end

  test "triggers eth wallet signal when balance increases", context do
    test_pid = self()

    with_mocks [
      {Sanbase.Telegram, [:passthrough],
       send_message: fn _user, text ->
         send(test_pid, {:telegram_to_self, text})
         {:ok, "OK"}
       end},
      {HistoricalBalance, [:passthrough],
       balance_change: fn _, _, _, _ ->
         {:ok,
          [
            %{
              address: context.eth_address,
              balance_start: 20,
              balance_end: 70,
              balance_change_amount: 50,
              balance_change_percent: 250.0
            }
          ]}
       end}
    ] do
      Scheduler.run_alert(EthWalletTriggerSettings)

      assert_receive({:telegram_to_self, message})

      assert message =~
               "**#{context.project.name}**'s ethereum balance increased by 50"

      assert message =~ "was: 20, now: 70"
    end
  end

  test "triggers eth wallet and address alerts when balance increases", context do
    test_pid = self()

    with_mocks [
      {Sanbase.Telegram, [:passthrough],
       send_message: fn _user, text ->
         send(test_pid, {:telegram_to_self, text})
         {:ok, "OK"}
       end},
      {HistoricalBalance, [:passthrough],
       balance_change: fn _, _, _, _ ->
         {:ok,
          [
            %{
              address: context.eth_address,
              balance_start: 20,
              balance_end: 300,
              balance_change_amount: 280,
              balance_change_percent: 1400.0
            }
          ]}
       end}
    ] do
      Scheduler.run_alert(EthWalletTriggerSettings)

      assert_receive({:telegram_to_self, message1})
      assert_receive({:telegram_to_self, message2})

      # Plain sort won't work as depends on the randomly generated project name
      # Sorting on wheter there is `address` substring is deterministic
      sorted_messages = Enum.sort_by([message1, message2], &String.contains?(&1, "address"))

      assert Enum.at(sorted_messages, 0) =~
               "**#{context.project.name}**'s ethereum balance increased by 280"

      assert Enum.at(sorted_messages, 1) =~
               "The address #{context.eth_address}'s ethereum balance increased by 280"
    end
  end

  test "triggers address signal when balance decreases", context do
    test_pid = self()

    with_mocks [
      {Sanbase.Telegram, [:passthrough],
       send_message: fn _user, text ->
         send(test_pid, {:telegram_to_self, text})
         {:ok, "OK"}
       end},
      {HistoricalBalance, [:passthrough],
       balance_change: fn _, _, _, _ ->
         {:ok,
          [
            %{
              address: context.eth_address,
              balance_start: 100,
              balance_end: 0,
              balance_change_amount: -100,
              balance_change_percent: -100.0
            }
          ]}
       end}
    ] do
      Scheduler.run_alert(EthWalletTriggerSettings)

      assert_receive({:telegram_to_self, message})

      assert message =~
               "🔔 The address #{context.eth_address}'s ethereum balance decreased by 100"
    end
  end

  test "behavior is correct in case of database error" do
    test_pid = self()

    with_mocks [
      {Sanbase.Telegram, [:passthrough],
       send_message: fn _user, text ->
         send(test_pid, {:telegram_to_self, text})
         {:ok, "OK"}
       end},
      {HistoricalBalance, [:passthrough],
       balance_change: fn _, _, _, _ ->
         {:error, "Something bad happened"}
       end}
    ] do
      Scheduler.run_alert(EthWalletTriggerSettings)

      refute_receive({:telegram_to_self, _})
    end
  end
end
