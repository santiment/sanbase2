defmodule Sanbase.Signals.TriggerHistoryTest do
  use Sanbase.DataCase, async: false

  import Mock
  import Sanbase.Factory
  import Sanbase.DateTimeUtils

  alias Sanbase.Signals.UserTrigger
  alias Sanbase.Signals.History.Utils

  test "#moving_average_excluding_last" do
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

    sma = Utils.moving_average_excluding_last(daa_result, 1, :active_addresses)
    assert sma == {:error, "Cannot calculate moving average for these args"}

    {:ok, sma} = Utils.moving_average_excluding_last(daa_result, 2, :active_addresses)
    assert get_averages(sma) == [23.0, 25.0, 60.0, 30.0, 20.0, 76.0, 20.0, 50.0, 60.0]

    {:ok, sma} = Utils.moving_average_excluding_last(daa_result, 3, :active_addresses)
    assert get_averages(sma) == [24.0, 42.5, 45.0, 25.0, 48.0, 48.0, 35.0, 55.0]

    {:ok, sma} = Utils.moving_average_excluding_last(daa_result, 4, :active_addresses)
    assert get_averages(sma) == [36.0, 38.33, 36.67, 42.0, 38.67, 48.67, 43.33]
  end

  defp get_averages(sma_result) do
    Enum.map(sma_result, fn point -> Map.get(point, :average) end)
  end
end
