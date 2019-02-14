defmodule Sanbase.Signals.TriggerHistoryTest do
  use Sanbase.DataCase, async: false

  import Mock
  import Sanbase.Factory
  import Sanbase.DateTimeUtils

  alias Sanbase.Signals.UserTrigger

  test "returns historical data with trigger points" do
    with_mock Sanbase.Clickhouse.Erc20DailyActiveAddresses,
      average_active_addresses: fn _, _, _, _ ->
        {:ok,
         [
           %{datetime: from_iso8601!("2018-11-17T00:00:00Z"), active_addresses: 23},
           %{datetime: from_iso8601!("2018-11-18T00:00:00Z"), active_addresses: 25},
           %{datetime: from_iso8601!("2018-11-19T00:00:00Z"), active_addresses: 60},
           %{datetime: from_iso8601!("2018-11-20T00:00:00Z"), active_addresses: 30},
           %{datetime: from_iso8601!("2018-11-21T00:00:00Z"), active_addresses: 20},
           # this is trigger point
           %{datetime: from_iso8601!("2018-11-22T00:00:00Z"), active_addresses: 76},
           %{datetime: from_iso8601!("2018-11-23T00:00:00Z"), active_addresses: 20},
           %{datetime: from_iso8601!("2018-11-24T00:00:00Z"), active_addresses: 50},
           %{datetime: from_iso8601!("2018-11-25T00:00:00Z"), active_addresses: 60},
           %{datetime: from_iso8601!("2018-11-26T00:00:00Z"), active_addresses: 70}
         ]}
      end do
      trigger_settings = %{
        type: "daily_active_addresses",
        target: "santiment",
        channel: "telegram",
        time_window: "2d",
        percent_threshold: 200.0
      }

      insert(:project, %{
        ticker: "Santiment",
        coinmarketcap_id: "santiment",
        main_contract_address: "0x123"
      })

      trigger = %{settings: trigger_settings}
      {:ok, points} = UserTrigger.historical_trigger_points(trigger)

      triggered? =
        points
        |> Enum.find(fn %{datetime: dt} -> DateTime.to_iso8601(dt) == "2018-11-22T00:00:00Z" end)
        |> Map.get(:triggered?)

      assert Enum.map(points, fn point -> Map.get(point, :average_daa) end) == [
               nil,
               nil,
               24,
               43,
               45,
               25,
               48,
               48,
               35,
               55
             ]

      assert Enum.filter(points, fn point -> point.triggered? end) |> length() == 1
      assert Enum.filter(points, fn point -> !point.triggered? end) |> length() == 9
      assert length(points) == 10
      assert triggered? == true
    end
  end
end
