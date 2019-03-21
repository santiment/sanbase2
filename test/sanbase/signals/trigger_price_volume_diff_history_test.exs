defmodule Sanbase.Signals.PriceVolumeDiffHistoryTest do
  use Sanbase.DataCase, async: false

  import Mock
  import Sanbase.Factory
  import ExUnit.CaptureLog

  alias Sanbase.Signals.UserTrigger
  alias Sanbase.Signals.History.PriceVolumeDifferenceHistory

  @ticker "SAN"
  @cmc_id "santiment"
  @moduletag capture_log: true

  setup do
    Sanbase.Signals.Evaluator.Cache.clear()

    Sanbase.Factory.insert(:project, %{
      name: "Santiment",
      ticker: @ticker,
      coinmarketcap_id: @cmc_id,
      main_contract_address: "0x7c5a0ce9267ed19b22f8cae653f198e3e8daf098"
    })

    trigger = %{
      cooldown: "2h",
      settings: %{
        type: "price_volume_difference",
        target: %{slug: "santiment"},
        channel: "telegram",
        threshold: 0.015
      }
    }

    [
      trigger: trigger
    ]
  end

  test "works correct with ok response from tech_indicators", context do
    datetime1 = Timex.shift(Timex.now(), hours: -4) |> DateTime.truncate(:second)
    datetime2 = Timex.shift(Timex.now(), hours: -3) |> DateTime.truncate(:second)
    datetime3 = Timex.shift(Timex.now(), hours: -2) |> DateTime.truncate(:second)
    datetime4 = Timex.shift(Timex.now(), hours: -1) |> DateTime.truncate(:second)
    datetime5 = Timex.now() |> DateTime.truncate(:second)

    with_mock HTTPoison, [],
      get: fn _, _, _ ->
        {:ok,
         %HTTPoison.Response{
           body: """
           [
             {
               "price_volume_diff": 0.01,
               "price_change": 0.0005,
               "volume_change": 0.03,
               "timestamp": #{datetime1 |> DateTime.to_unix()}
              },
              {
               "price_volume_diff": 0.02,
               "price_change": 0.05,
               "volume_change": 0.03,
               "timestamp": #{datetime2 |> DateTime.to_unix()}
              },
             {
               "price_volume_diff": 0.03,
               "price_change": 0.04,
               "volume_change": 0.03,
               "timestamp": #{datetime3 |> DateTime.to_unix()}
              },
              {
               "price_volume_diff": 0.04,
               "price_change": 0.04,
               "volume_change": 0.03,
               "timestamp": #{datetime4 |> DateTime.to_unix()}
              },
              {
               "price_volume_diff": 0.003,
               "price_change": 0.04,
               "volume_change": 0.03,
               "timestamp": #{datetime5 |> DateTime.to_unix()}
              }
           ]
           """,
           status_code: 200
         }}
      end do
      {:ok, triggered_points} = UserTrigger.historical_trigger_points(context.trigger)

      assert triggered_points == [
               %{
                 datetime: datetime1,
                 price_change: 0.0005,
                 price_volume_diff: 0.01,
                 triggered?: false,
                 volume_change: 0.03
               },
               %{
                 datetime: datetime2,
                 price_change: 0.05,
                 price_volume_diff: 0.02,
                 triggered?: true,
                 volume_change: 0.03
               },
               %{
                 datetime: datetime3,
                 price_change: 0.04,
                 price_volume_diff: 0.03,
                 triggered?: false,
                 volume_change: 0.03
               },
               %{
                 datetime: datetime4,
                 price_change: 0.04,
                 price_volume_diff: 0.04,
                 triggered?: true,
                 volume_change: 0.03
               },
               %{
                 datetime: datetime5,
                 price_change: 0.04,
                 price_volume_diff: 0.003,
                 triggered?: false,
                 volume_change: 0.03
               }
             ]
    end
  end

  test "works correct with error respons from tech_indicators", context do
    with_mock HTTPoison, [],
      get: fn _, _, _ ->
        {:error, %HTTPoison.Error{reason: :econnrefused}}
      end do
      {:error, error_msg} = UserTrigger.historical_trigger_points(context.trigger)
      assert error_msg =~ "Error executing query. See logs for details"
    end
  end
end
