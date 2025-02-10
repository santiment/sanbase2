defmodule Sanbase.Alert.EthWalletTriggerHistoryTest do
  use Sanbase.DataCase, async: false

  import Mock

  alias Sanbase.Alert.UserTrigger
  alias Sanbase.Clickhouse.HistoricalBalance

  setup do
    Sanbase.Cache.clear_all(:alerts_evaluator_cache)

    project = Sanbase.Factory.insert(:random_erc20_project)

    trigger_settings_down = %{
      type: "eth_wallet",
      target: %{slug: project.slug},
      asset: %{slug: "ethereum"},
      channel: "telegram",
      operation: %{amount_down: 10}
    }

    trigger_settings_up = %{
      type: "eth_wallet",
      target: %{slug: project.slug},
      asset: %{slug: "ethereum"},
      channel: "telegram",
      operation: %{amount_up: 100}
    }

    [
      project: project,
      trigger_settings_down: trigger_settings_down,
      trigger_settings_up: trigger_settings_up
    ]
  end

  test "eth wallet signal when balance decreases", context do
    with_mock HistoricalBalance, [:passthrough],
      historical_balance: fn _, _, _, _, _ ->
        {:ok,
         [
           %{datetime: ~U[2019-01-01 00:00:00Z], balance: 100},
           %{datetime: ~U[2019-01-01 01:00:00Z], balance: 100},
           %{datetime: ~U[2019-01-01 02:00:00Z], balance: 50},
           %{datetime: ~U[2019-01-01 03:00:00Z], balance: 50},
           %{datetime: ~U[2019-01-01 04:00:00Z], balance: 50},
           %{datetime: ~U[2019-01-01 05:00:00Z], balance: 50},
           %{datetime: ~U[2019-01-01 06:00:00Z], balance: 20},
           %{datetime: ~U[2019-01-01 07:00:00Z], balance: 20},
           %{datetime: ~U[2019-01-01 08:00:00Z], balance: 10}
         ]}
      end do
      expected_result =
        {:ok,
         [
           %{balance: 100, datetime: ~U[2019-01-01 00:00:00Z], triggered?: false},
           %{balance: 100, datetime: ~U[2019-01-01 01:00:00Z], triggered?: false},
           %{balance: 50, datetime: ~U[2019-01-01 02:00:00Z], triggered?: true},
           %{balance: 50, datetime: ~U[2019-01-01 03:00:00Z], triggered?: false},
           %{balance: 50, datetime: ~U[2019-01-01 04:00:00Z], triggered?: false},
           %{balance: 50, datetime: ~U[2019-01-01 05:00:00Z], triggered?: false},
           %{balance: 20, datetime: ~U[2019-01-01 06:00:00Z], triggered?: true},
           %{balance: 20, datetime: ~U[2019-01-01 07:00:00Z], triggered?: false},
           %{balance: 10, datetime: ~U[2019-01-01 08:00:00Z], triggered?: true}
         ]}

      assert UserTrigger.historical_trigger_points(%{
               cooldown: "30m",
               settings: context.trigger_settings_down
             }) == expected_result
    end
  end

  test "eth wallet signal with big cooldown when balance decreases", context do
    with_mock HistoricalBalance, [:passthrough],
      historical_balance: fn _, _, _, _, _ ->
        {:ok,
         [
           %{datetime: ~U[2019-01-01 00:00:00Z], balance: 100},
           %{datetime: ~U[2019-01-01 01:00:00Z], balance: 100},
           %{datetime: ~U[2019-01-01 02:00:00Z], balance: 50},
           %{datetime: ~U[2019-01-01 03:00:00Z], balance: 50},
           %{datetime: ~U[2019-01-01 04:00:00Z], balance: 50},
           %{datetime: ~U[2019-01-01 05:00:00Z], balance: 50},
           %{datetime: ~U[2019-01-01 06:00:00Z], balance: 20},
           %{datetime: ~U[2019-01-01 07:00:00Z], balance: 20},
           %{datetime: ~U[2019-01-01 08:00:00Z], balance: 10}
         ]}
      end do
      expected_result =
        {:ok,
         [
           %{balance: 100, datetime: ~U[2019-01-01 00:00:00Z], triggered?: false},
           %{balance: 100, datetime: ~U[2019-01-01 01:00:00Z], triggered?: false},
           %{balance: 50, datetime: ~U[2019-01-01 02:00:00Z], triggered?: true},
           %{balance: 50, datetime: ~U[2019-01-01 03:00:00Z], triggered?: false},
           %{balance: 50, datetime: ~U[2019-01-01 04:00:00Z], triggered?: false},
           %{balance: 50, datetime: ~U[2019-01-01 05:00:00Z], triggered?: false},
           %{balance: 20, datetime: ~U[2019-01-01 06:00:00Z], triggered?: false},
           %{balance: 20, datetime: ~U[2019-01-01 07:00:00Z], triggered?: false},
           %{balance: 10, datetime: ~U[2019-01-01 08:00:00Z], triggered?: false}
         ]}

      assert UserTrigger.historical_trigger_points(%{
               cooldown: "1d",
               settings: context.trigger_settings_down
             }) == expected_result
    end
  end

  test "eth wallet signal when balance increases", context do
    with_mock HistoricalBalance, [:passthrough],
      historical_balance: fn _, _, _, _, _ ->
        {:ok,
         [
           %{datetime: ~U[2019-01-01 00:00:00Z], balance: 100},
           %{datetime: ~U[2019-01-01 01:00:00Z], balance: 1000},
           %{datetime: ~U[2019-01-01 02:00:00Z], balance: 2000},
           %{datetime: ~U[2019-01-01 03:00:00Z], balance: 2000},
           %{datetime: ~U[2019-01-01 04:00:00Z], balance: 2000},
           %{datetime: ~U[2019-01-01 05:00:00Z], balance: 2000},
           %{datetime: ~U[2019-01-01 06:00:00Z], balance: 2500},
           %{datetime: ~U[2019-01-01 07:00:00Z], balance: 2500},
           %{datetime: ~U[2019-01-01 08:00:00Z], balance: 2500}
         ]}
      end do
      expected_result =
        {:ok,
         [
           %{balance: 100, datetime: ~U[2019-01-01 00:00:00Z], triggered?: false},
           %{balance: 1000, datetime: ~U[2019-01-01 01:00:00Z], triggered?: true},
           %{balance: 2000, datetime: ~U[2019-01-01 02:00:00Z], triggered?: true},
           %{balance: 2000, datetime: ~U[2019-01-01 03:00:00Z], triggered?: false},
           %{balance: 2000, datetime: ~U[2019-01-01 04:00:00Z], triggered?: false},
           %{balance: 2000, datetime: ~U[2019-01-01 05:00:00Z], triggered?: false},
           %{balance: 2500, datetime: ~U[2019-01-01 06:00:00Z], triggered?: true},
           %{balance: 2500, datetime: ~U[2019-01-01 07:00:00Z], triggered?: false},
           %{balance: 2500, datetime: ~U[2019-01-01 08:00:00Z], triggered?: false}
         ]}

      assert UserTrigger.historical_trigger_points(%{
               cooldown: "30m",
               settings: context.trigger_settings_up
             }) == expected_result
    end
  end

  test "eth wallet signal with big cooldown when balance increases", context do
    with_mock HistoricalBalance, [:passthrough],
      historical_balance: fn _, _, _, _, _ ->
        {:ok,
         [
           %{datetime: ~U[2019-01-01 00:00:00Z], balance: 100},
           %{datetime: ~U[2019-01-01 01:00:00Z], balance: 1000},
           %{datetime: ~U[2019-01-01 02:00:00Z], balance: 2000},
           %{datetime: ~U[2019-01-01 03:00:00Z], balance: 2000},
           %{datetime: ~U[2019-01-01 04:00:00Z], balance: 2000},
           %{datetime: ~U[2019-01-01 05:00:00Z], balance: 2000},
           %{datetime: ~U[2019-01-01 06:00:00Z], balance: 2500},
           %{datetime: ~U[2019-01-01 07:00:00Z], balance: 2500},
           %{datetime: ~U[2019-01-01 08:00:00Z], balance: 2500}
         ]}
      end do
      expected_result =
        {:ok,
         [
           %{balance: 100, datetime: ~U[2019-01-01 00:00:00Z], triggered?: false},
           %{balance: 1000, datetime: ~U[2019-01-01 01:00:00Z], triggered?: true},
           %{balance: 2000, datetime: ~U[2019-01-01 02:00:00Z], triggered?: false},
           %{balance: 2000, datetime: ~U[2019-01-01 03:00:00Z], triggered?: false},
           %{balance: 2000, datetime: ~U[2019-01-01 04:00:00Z], triggered?: false},
           %{balance: 2000, datetime: ~U[2019-01-01 05:00:00Z], triggered?: false},
           %{balance: 2500, datetime: ~U[2019-01-01 06:00:00Z], triggered?: false},
           %{balance: 2500, datetime: ~U[2019-01-01 07:00:00Z], triggered?: false},
           %{balance: 2500, datetime: ~U[2019-01-01 08:00:00Z], triggered?: false}
         ]}

      assert UserTrigger.historical_trigger_points(%{
               cooldown: "1d",
               settings: context.trigger_settings_up
             }) == expected_result
    end
  end

  test "eth wallet signal historical data not implemented for % change", context do
    trigger_settings = %{
      type: "eth_wallet",
      target: %{slug: context.project.slug},
      asset: %{slug: "ethereum"},
      channel: "telegram",
      operation: %{percent_up: 10}
    }

    assert UserTrigger.historical_trigger_points(%{
             cooldown: "1d",
             settings: trigger_settings
           }) == {:error, "Historical trigger points for percent change are not implemented"}
  end
end
