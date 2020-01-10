defmodule Sanbase.Signal.TriggerPriceHistoryTest do
  use Sanbase.DataCase, async: false

  import Mock
  import Sanbase.Factory
  import Sanbase.DateTimeUtils

  alias Sanbase.Signal.UserTrigger

  test "returns historical price data with trigger points for percent change" do
    prices_result = [
      [from_iso8601!("2018-11-17T00:00:00Z"), 20, 1000, 500, 200],
      [from_iso8601!("2018-11-18T00:00:00Z"), 25, 1000, 500, 200],
      [from_iso8601!("2018-11-19T00:00:00Z"), 30, 1000, 500, 200],
      # trigger point
      [from_iso8601!("2018-11-20T00:00:00Z"), 25, 1000, 500, 200],
      [from_iso8601!("2018-11-21T00:00:00Z"), 20, 1000, 500, 200],
      [from_iso8601!("2018-11-22T00:00:00Z"), 20, 1000, 500, 200],
      [from_iso8601!("2018-11-23T00:00:00Z"), 20, 1000, 500, 200],
      [from_iso8601!("2018-11-24T00:00:00Z"), 20, 1000, 500, 200],
      [from_iso8601!("2018-11-25T00:00:00Z"), 20, 1000, 500, 200],
      # trigger point
      [from_iso8601!("2018-11-26T00:00:00Z"), 21, 1000, 500, 200],
      [from_iso8601!("2018-11-27T00:00:00Z"), 22, 1000, 500, 200],
      # cooldown
      [from_iso8601!("2018-11-28T00:00:00Z"), 25, 1000, 500, 200],
      # cooldown
      [from_iso8601!("2018-11-29T00:00:00Z"), 28, 1000, 500, 200],
      # cooldown
      [from_iso8601!("2018-11-30T00:00:00Z"), 45, 1000, 500, 200],
      # trigger point
      [from_iso8601!("2018-12-01T00:00:00Z"), 47, 1000, 500, 200],
      # cooldown
      [from_iso8601!("2018-12-02T00:00:00Z"), 50, 1000, 500, 200],
      # cooldown
      [from_iso8601!("2018-12-03T00:00:00Z"), 50, 1000, 500, 200]
    ]

    with_mock Sanbase.Prices.Store,
      fetch_prices_with_resolution: fn _, _, _, _ ->
        {:ok, prices_result}
      end do
      percent_threshold = 5.0

      trigger = %{
        cooldown: "4h",
        settings: %{
          type: "price_percent_change",
          target: %{slug: "santiment"},
          channel: "telegram",
          time_window: "4h",
          operation: %{percent_up: percent_threshold}
        }
      }

      insert(:project, %{
        ticker: "SAN",
        slug: "santiment",
        main_contract_address: "0x123"
      })

      {:ok, points} = UserTrigger.historical_trigger_points(trigger)
      assert length(points) == 17
      trigger_points = Enum.filter(points, fn point -> point.triggered? end)
      assert length(trigger_points) == 3

      assert trigger_points |> Enum.map(fn point -> point.datetime end) ==
               [
                 from_iso8601!("2018-11-20T00:00:00Z"),
                 from_iso8601!("2018-11-26T00:00:00Z"),
                 from_iso8601!("2018-12-01T00:00:00Z")
               ]

      # cooldowns
      assert Enum.filter(points, fn point ->
               !point.triggered? and point.percent_change > percent_threshold
             end)
             |> length() == 6
    end
  end

  test "returns historical price data with trigger points for absolute change" do
    prices_result = [
      [from_iso8601!("2018-11-17T00:00:00Z"), 20, 1000, 500, 200],
      # trigger point
      [from_iso8601!("2018-11-18T00:00:00Z"), 25, 1000, 500, 200],
      # cooldown
      [from_iso8601!("2018-11-19T00:00:00Z"), 30, 1000, 500, 200],
      # cooldown
      [from_iso8601!("2018-11-20T00:00:00Z"), 25, 1000, 500, 200],
      [from_iso8601!("2018-11-21T00:00:00Z"), 20, 1000, 500, 200],
      [from_iso8601!("2018-11-22T00:00:00Z"), 20, 1000, 500, 200],
      [from_iso8601!("2018-11-23T00:00:00Z"), 20, 1000, 500, 200],
      [from_iso8601!("2018-11-24T00:00:00Z"), 20, 1000, 500, 200],
      [from_iso8601!("2018-11-25T00:00:00Z"), 20, 1000, 500, 200],
      # trigger point
      [from_iso8601!("2018-11-26T00:00:00Z"), 21, 1000, 500, 200],
      # cooldown
      [from_iso8601!("2018-11-27T00:00:00Z"), 22, 1000, 500, 200],
      # cooldown
      [from_iso8601!("2018-11-28T00:00:00Z"), 25, 1000, 500, 200],
      # cooldown
      [from_iso8601!("2018-11-29T00:00:00Z"), 28, 1000, 500, 200],
      # cooldown
      [from_iso8601!("2018-11-30T00:00:00Z"), 45, 1000, 500, 200],
      # trigger point
      [from_iso8601!("2018-12-01T00:00:00Z"), 47, 1000, 500, 200],
      # cooldown
      [from_iso8601!("2018-12-02T00:00:00Z"), 50, 1000, 500, 200],
      # cooldown
      [from_iso8601!("2018-12-03T00:00:00Z"), 50, 1000, 500, 200]
    ]

    with_mock Sanbase.Prices.Store,
      fetch_prices_with_resolution: fn _, _, _, _ ->
        {:ok, prices_result}
      end do
      trigger = %{
        cooldown: "4h",
        settings: %{
          type: "price_absolute_change",
          target: %{slug: "santiment"},
          channel: "telegram",
          operation: %{above: 21.0}
        }
      }

      insert(:project, %{
        ticker: "SAN",
        slug: "santiment",
        main_contract_address: "0x123"
      })

      {:ok, points} = UserTrigger.historical_trigger_points(trigger)
      assert length(points) == 17
      trigger_points = Enum.filter(points, fn point -> point.triggered? end)
      assert length(trigger_points) == 3

      assert trigger_points |> Enum.map(fn point -> point.datetime end) ==
               [
                 from_iso8601!("2018-11-18T00:00:00Z"),
                 from_iso8601!("2018-11-26T00:00:00Z"),
                 from_iso8601!("2018-12-01T00:00:00Z")
               ]

      # cooldowns
      assert Enum.filter(points, fn point ->
               !point.triggered? and point.price > trigger.settings.operation.above
             end)
             |> length() == 8
    end
  end
end
