defmodule Sanbase.Alert.WalletAssetsHeldTriggerSettingsTest do
  use Sanbase.DataCase, async: false

  import Sanbase.Factory
  import ExUnit.CaptureLog

  alias Sanbase.Alert.{
    UserTrigger,
    Trigger.WalletAssetsHeldTriggerSettings,
    Scheduler
  }

  alias Sanbase.Clickhouse.HistoricalBalance

  setup do
    # Some of the code needs to run in the web pod while creating the asset
    # to do the initial setup. That's why we need to clear both caches
    Sanbase.Cache.clear_all()
    Sanbase.Cache.clear_all(:alerts_evaluator_cache)

    user = insert(:user, user_settings: %{settings: %{alert_notify_telegram: true}})

    Sanbase.Accounts.UserSettings.set_telegram_chat_id(user.id, 123_123_123_123)

    # Provide this mixed case (both lower and upper case letters) to the trigger settings
    # to test the behavior of transform to some internal format.
    address = "0x77Fd8239ECf7aBcEaF9F2c14F5aCAE950e7B3e98"

    settings = %{
      type: "wallet_assets_held",
      selector: %{infrastructure: "ETH"},
      target: %{address: address},
      channel: "telegram",
      time_window: "1d"
    }

    for project_map <- projects() do
      # Create the projects as the code that generates the insight
      insert(:random_erc20_project, project_map)
    end

    %{address: address, settings: settings, user: user}
  end

  test "cooldown works for wallet_assets_held", context do
    mock_fun =
      [
        # The first call is setting up the state after creation
        fn -> {:ok, []} end,
        # The second call is returning some different data so the alert fires
        fn -> {:ok, data()} end
      ]
      |> Sanbase.Mock.wrap_consecutives(arity: 1)

    Sanbase.Mock.prepare_mock2(&Sanbase.Telegram.send_message/2, {:ok, "OK"})
    |> Sanbase.Mock.prepare_mock(HistoricalBalance, :assets_held_by_address, mock_fun)
    |> Sanbase.Mock.run_with_mocks(fn ->
      for _ <- 1..2 do
        {:ok, _} =
          UserTrigger.create_user_trigger(
            context.user,
            %{title: "title", is_public: true, cooldown: "1d", settings: context.settings}
          )
      end

      # Clear the cache after creating the triggers so the cached call to the HistoricalBalance
      # module that is used to initialize the states is cleared. In the next evaluation it should
      # call the second function in the mock_fun list
      Sanbase.Cache.clear_all()
      Sanbase.Cache.clear_all(:alerts_evaluator_cache)

      log = capture_log(fn -> Scheduler.run_alert(WalletAssetsHeldTriggerSettings) end)
      assert log =~ "In total 2/2 wallet_assets_held alerts were sent successfully"

      Sanbase.Cache.clear_all()
      Sanbase.Cache.clear_all(:alerts_evaluator_cache)

      assert capture_log(fn -> Scheduler.run_alert(WalletAssetsHeldTriggerSettings) end) =~
               "There were no wallet_assets_held alerts triggered"
    end)
  end

  test "some alerts trigger", context do
    mock_fun =
      [
        # The first call is setting up the state after creation
        fn -> {:ok, []} end,
        # The second call is returning some different data so the alert fires
        fn -> {:ok, data()} end
      ]
      |> Sanbase.Mock.wrap_consecutives(arity: 1)

    test_pid = self()

    telegram_mock_fun = fn _user, text ->
      send(test_pid, {:telegram_to_self, text})
      {:ok, "OK"}
    end

    Sanbase.Mock.prepare_mock(Sanbase.Telegram, :send_message, telegram_mock_fun)
    |> Sanbase.Mock.prepare_mock(HistoricalBalance, :assets_held_by_address, mock_fun)
    |> Sanbase.Mock.run_with_mocks(fn ->
      for _ <- 1..2 do
        {:ok, _} =
          UserTrigger.create_user_trigger(
            context.user,
            %{title: "title", is_public: true, cooldown: "1d", settings: context.settings}
          )
      end

      # Clear the cache after creating the triggers so the cached call to the HistoricalBalance
      # module that is used to initialize the states is cleared. In the next evaluation it should
      # call the second function in the mock_fun list
      Sanbase.Cache.clear_all()
      Sanbase.Cache.clear_all(:alerts_evaluator_cache)

      Scheduler.run_alert(WalletAssetsHeldTriggerSettings)
      assert_receive({:telegram_to_self, message})

      assert message =~
               "🔔 The address 0x77Fd8239ECf7aBcEaF9F2c14F5aCAE950e7B3e98 assets held has changed"

      assert message =~ "5 Newcomers:"
      assert message =~ "[#ETH | Ethereum](https://app-stage.santiment.net/projects/ethereum)"
      assert message =~ "[#BTC | Bitcoin](https://app-stage.santiment.net/projects/bitcoin)"
      assert message =~ "[#MKR | Maker](https://app-stage.santiment.net/projects/maker)"
      assert message =~ "[#STJ | Storj](https://app-stage.santiment.net/projects/storj)"
      assert message =~ "[#UNI | Uniswap](https://app-stage.santiment.net/projects/uniswap)"
      assert message =~ "--"
      assert message =~ "0 Leavers:"
    end)
  end

  defp projects(),
    do: [
      %{slug: "ethereum", name: "Ethereum", ticker: "ETH"},
      %{slug: "bitcoin", name: "Bitcoin", ticker: "BTC"},
      %{slug: "maker", name: "Maker", ticker: "MKR"},
      %{slug: "storj", name: "Storj", ticker: "STJ"},
      %{slug: "uniswap", name: "Uniswap", ticker: "UNI"}
    ]

  defp data() do
    [
      %{
        current_balance: 1_924_082.265599849,
        current_price_usd: 469.0361356389575,
        current_usd_value: 902_464_110.5084034,
        slug: Enum.at(projects(), 0).slug
      },
      %{
        current_balance: 14_600_299_531.569061,
        current_price_usd: 0.05163,
        current_usd_value: 753_813_464.8149107,
        slug: Enum.at(projects(), 1).slug
      },
      %{
        current_balance: 16_030_443.377157,
        current_price_usd: 1.6967803881577543,
        current_usd_value: 27_200_141.935833357,
        slug: Enum.at(projects(), 2).slug
      },
      %{
        current_balance: 75_000_002.05912834,
        current_price_usd: 0.9601,
        current_usd_value: 72_007_501.97696912,
        slug: Enum.at(projects(), 3).slug
      },
      %{
        current_balance: 500_000_057.10439026,
        current_price_usd: 0.28336596302872935,
        current_usd_value: 141_682_997.69580522,
        slug: Enum.at(projects(), 4).slug
      }
    ]
  end
end
