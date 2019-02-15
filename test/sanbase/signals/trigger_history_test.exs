defmodule Sanbase.Signals.TriggerHistoryTest do
  use Sanbase.DataCase, async: false

  import Mock
  import Sanbase.Factory
  import Sanbase.DateTimeUtils

  alias Sanbase.Signals.UserTrigger
  alias Sanbase.Prices.Store
  alias Sanbase.Influxdb.Measurement

  test "returns historical daa data with trigger points" do
    daa_result = [
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
    ]

    with_mock Sanbase.Clickhouse.Erc20DailyActiveAddresses,
      average_active_addresses: fn _, _, _, _ ->
        {:ok, daa_result}
      end do
      trigger_settings = %{
        type: "daily_active_addresses",
        target: "santiment",
        channel: "telegram",
        time_window: "2d",
        percent_threshold: 200.0
      }

      insert(:project, %{
        ticker: "SAN",
        coinmarketcap_id: "santiment",
        main_contract_address: "0x123"
      })

      datetimes = daa_result |> Enum.map(fn %{datetime: dt} -> dt end)
      populate_influxdb(datetimes, "SAN_santiment")

      trigger = %{settings: trigger_settings}
      {:ok, points} = UserTrigger.historical_trigger_points(trigger)

      triggered? =
        points
        |> Enum.find(fn %{datetime: dt} -> DateTime.to_iso8601(dt) == "2018-11-22T00:00:00Z" end)
        |> Map.get(:triggered?)

      assert Enum.map(points, fn point -> Map.get(point, :average) end) == [
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

  test "returns historical price data with trigger points" do
    trigger_settings = %{
      type: "price_percent_change",
      target: "santiment",
      channel: "telegram",
      time_window: "1h",
      percent_threshold: 0.05
    }

    insert(:project, %{
      ticker: "SAN",
      coinmarketcap_id: "santiment",
      main_contract_address: "0x123"
    })

    populate_influxdb("SAN_santiment")

    trigger = %{settings: trigger_settings}
    {:ok, points} = UserTrigger.historical_trigger_points(trigger)
    assert length(points) == 10
    assert Enum.filter(points, fn point -> point.triggered? end) |> length() == 9
  end

  defp populate_influxdb(datetimes, ticker_cmc_id) do
    Store.drop_measurement(ticker_cmc_id)

    datetimes
    |> Enum.map(fn dt ->
      %Measurement{
        timestamp: dt |> DateTime.to_unix(:nanosecond),
        fields: %{price_usd: 20, price_btc: 1000, volume_usd: 200, marketcap_usd: 500},
        name: ticker_cmc_id
      }
    end)
    |> Store.import()
  end

  defp populate_influxdb(ticker_cmc_id) do
    Store.drop_measurement(ticker_cmc_id)
    now = Timex.now()
    step = 3600
    price_step = 0.01

    for x <- 0..9 do
      %Measurement{
        timestamp: Timex.shift(now, seconds: -3600 * x) |> DateTime.to_unix(:nanosecond),
        fields: %{
          price_usd: 20 - 20 * 0.01 * x,
          price_btc: 1000,
          volume_usd: 200,
          marketcap_usd: 500
        },
        name: ticker_cmc_id
      }
    end
    |> Store.import()
  end
end
