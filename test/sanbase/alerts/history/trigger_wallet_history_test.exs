defmodule Sanbase.Alert.WalletTriggerHistoryTest do
  use Sanbase.DataCase, async: false

  import Mock

  alias Sanbase.Alert.UserTrigger
  alias Sanbase.Clickhouse.HistoricalBalance

  setup do
    Sanbase.Cache.clear_all(:alerts_evaluator_cache)

    project = Sanbase.Factory.insert(:random_erc20_project)

    trigger_settings_down = %{
      type: "wallet_movement",
      target: %{slug: project.slug},
      selector: %{infrastructure: "ETH", slug: "ethereum"},
      channel: "telegram",
      operation: %{amount_down: 10}
    }

    trigger_settings_up = %{
      type: "wallet_movement",
      target: %{slug: project.slug},
      selector: %{infrastructure: "XRP", curreny: "BTC"},
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
      {:ok, points} =
        UserTrigger.historical_trigger_points(%{
          cooldown: "30m",
          settings: context.trigger_settings_down
        })

      assert points |> Enum.filter(& &1.triggered?) |> length() == 3
      assert points |> Enum.filter(&(not &1.triggered?)) |> length() == 5

      assert length(points) == 8

      assert points
             |> Enum.find(fn %{datetime: dt} ->
               DateTime.to_iso8601(dt) == "2019-01-01T02:00:00Z"
             end)
             |> Map.get(:triggered?) == true

      assert points
             |> Enum.find(fn %{datetime: dt} ->
               DateTime.to_iso8601(dt) == "2019-01-01T06:00:00Z"
             end)
             |> Map.get(:triggered?) == true

      assert points
             |> Enum.find(fn %{datetime: dt} ->
               DateTime.to_iso8601(dt) == "2019-01-01T08:00:00Z"
             end)
             |> Map.get(:triggered?) == true
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
      {:ok, points} =
        UserTrigger.historical_trigger_points(%{
          cooldown: "1d",
          settings: context.trigger_settings_down
        })

      assert points |> Enum.filter(& &1.triggered?) |> length() == 1
      assert points |> Enum.filter(&(not &1.triggered?)) |> length() == 7

      assert length(points) == 8

      assert points
             |> Enum.find(fn %{datetime: dt} ->
               DateTime.to_iso8601(dt) == "2019-01-01T02:00:00Z"
             end)
             |> Map.get(:triggered?) == true
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
      {:ok, points} =
        UserTrigger.historical_trigger_points(%{
          cooldown: "30m",
          settings: context.trigger_settings_up
        })

      assert points |> Enum.filter(& &1.triggered?) |> length() == 3
      assert points |> Enum.filter(&(not &1.triggered?)) |> length() == 5

      assert length(points) == 8

      assert points
             |> Enum.find(fn %{datetime: dt} ->
               DateTime.to_iso8601(dt) == "2019-01-01T02:00:00Z"
             end)
             |> Map.get(:triggered?) == true

      assert points
             |> Enum.find(fn %{datetime: dt} ->
               DateTime.to_iso8601(dt) == "2019-01-01T02:00:00Z"
             end)
             |> Map.get(:triggered?) == true

      assert points
             |> Enum.find(fn %{datetime: dt} ->
               DateTime.to_iso8601(dt) == "2019-01-01T06:00:00Z"
             end)
             |> Map.get(:triggered?) == true
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
      {:ok, points} =
        UserTrigger.historical_trigger_points(%{
          cooldown: "1d",
          settings: context.trigger_settings_up
        })

      assert points |> Enum.filter(& &1.triggered?) |> length() == 1
      assert points |> Enum.filter(&(not &1.triggered?)) |> length() == 7

      assert length(points) == 8

      assert points
             |> Enum.find(fn %{datetime: dt} ->
               DateTime.to_iso8601(dt) == "2019-01-01T01:00:00Z"
             end)
             |> Map.get(:triggered?) == true
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
