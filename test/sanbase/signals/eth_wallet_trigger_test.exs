defmodule Sanbase.Signals.EthWalletTriggerTest do
  use Sanbase.DataCase, async: false

  import Mock
  import Sanbase.Factory

  alias Sanbase.Model.Project

  alias Sanbase.Signals.{
    UserTrigger,
    Trigger.EthWalletTriggerSettings,
    Scheduler
  }

  alias Sanbase.Clickhouse.HistoricalBalance

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

    slug = "santiment"

    project =
      Sanbase.Factory.insert(:project, %{
        coinmarketcap_id: slug,
        main_contract_address: "0x7c5a0ce9267ed19b22f8cae653f198e3e8daf098"
      })

    {:ok, [eth_address]} = Project.eth_addresses(project)

    trigger_settings1 = %{
      type: "eth_wallet",
      target: %{slug: slug},
      asset: %{slug: "ethereum"},
      channel: "telegram",
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
      eth_address: eth_address,
      user: user,
      trigger1: trigger1,
      trigger2: trigger2
    ]
  end

  test "triggers eth wallet signal", _context do
    test_pid = self()

    with_mocks [
      {Sanbase.Telegram, [:passthrough],
       send_message: fn _user, text ->
         send(test_pid, {:telegram_to_self, text})
         :ok
       end},
      {HistoricalBalance, [:passthrough],
       balance_change: fn _, _, _, _ ->
         {:ok, {20, 70, 50}}
       end}
    ] do
      Scheduler.run_signal(EthWalletTriggerSettings)

      assert_receive({:telegram_to_self, message})
      assert message =~ "The ethereum balance of Santiment wallets has changed by 50"
    end
  end

  test "triggers both eth wallet and address signals", context do
    test_pid = self()

    with_mocks [
      {Sanbase.Telegram, [:passthrough],
       send_message: fn _user, text ->
         send(test_pid, {:telegram_to_self, text})
         :ok
       end},
      {HistoricalBalance, [:passthrough],
       balance_change: fn _, _, _, _ ->
         {:ok, {20, 300, 280}}
       end}
    ] do
      Scheduler.run_signal(EthWalletTriggerSettings)

      assert_receive({:telegram_to_self, message})
      assert message =~ "The ethereum balance of Santiment wallets has changed by 280"

      assert_receive({:telegram_to_self, message})

      assert message =~
               "The ethereum balance of the address #{context.eth_address} has changed by 280"
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
      Scheduler.run_signal(EthWalletTriggerSettings)

      refute_receive({:telegram_to_self, _})
    end
  end
end
