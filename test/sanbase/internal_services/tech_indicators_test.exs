defmodule Sanbase.InternalServices.TechIndicatorsTest do
  use SanbaseWeb.ConnCase
  use Phoenix.ConnTest

  import Mockery

  alias Sanbase.InternalServices.TechIndicators

  test "fetch macd", context do
    mock(
      HTTPoison,
      :get,
      {:ok,
       %HTTPoison.Response{
         body:
           "[{\"macd\": 0.0, \"timestamp\": 1516406400000000000}, {\"macd\": -0.014954423076923185, \"timestamp\": 1516492800000000000}, {\"macd\": -0.02373337292856359, \"timestamp\": 1516579200000000000}, {\"macd\": -0.030529013702074614, \"timestamp\": 1516665600000000000}, {\"macd\": -0.0239400614928722, \"timestamp\": 1516752000000000000}]",
         status_code: 200
       }}
    )

    result =
      TechIndicators.macd(
        "XYZ",
        "USD",
        DateTime.from_unix!(1_516_406_400_000_000_000, :nanoseconds),
        DateTime.from_unix!(1_516_752_000_000_000_000, :nanoseconds),
        "1d"
      )

    assert result ==
             {:ok,
              [
                %{
                  macd: Decimal.new(0.0),
                  datetime: DateTime.from_unix!(1_516_406_400_000_000_000, :nanoseconds)
                },
                %{
                  macd: Decimal.new(-0.014954423076923185),
                  datetime: DateTime.from_unix!(1_516_492_800_000_000_000, :nanoseconds)
                },
                %{
                  macd: Decimal.new(-0.02373337292856359),
                  datetime: DateTime.from_unix!(1_516_579_200_000_000_000, :nanoseconds)
                },
                %{
                  macd: Decimal.new(-0.030529013702074614),
                  datetime: DateTime.from_unix!(1_516_665_600_000_000_000, :nanoseconds)
                },
                %{
                  macd: Decimal.new(-0.0239400614928722),
                  datetime: DateTime.from_unix!(1_516_752_000_000_000_000, :nanoseconds)
                }
              ]}
  end

  test "fetch rsi", context do
    mock(
      HTTPoison,
      :get,
      {:ok,
       %HTTPoison.Response{
         body:
           "[{\"rsi\": 0.0, \"timestamp\": 1516406400000000000}, {\"rsi\": -0.014954423076923185, \"timestamp\": 1516492800000000000}, {\"rsi\": -0.02373337292856359, \"timestamp\": 1516579200000000000}, {\"rsi\": -0.030529013702074614, \"timestamp\": 1516665600000000000}, {\"rsi\": -0.0239400614928722, \"timestamp\": 1516752000000000000}]",
         status_code: 200
       }}
    )

    result =
      TechIndicators.rsi(
        "XYZ",
        "USD",
        DateTime.from_unix!(1_516_406_400_000_000_000, :nanoseconds),
        DateTime.from_unix!(1_516_752_000_000_000_000, :nanoseconds),
        "1d",
        5
      )

    assert result ==
             {:ok,
              [
                %{
                  rsi: Decimal.new(0.0),
                  datetime: DateTime.from_unix!(1_516_406_400_000_000_000, :nanoseconds)
                },
                %{
                  rsi: Decimal.new(-0.014954423076923185),
                  datetime: DateTime.from_unix!(1_516_492_800_000_000_000, :nanoseconds)
                },
                %{
                  rsi: Decimal.new(-0.02373337292856359),
                  datetime: DateTime.from_unix!(1_516_579_200_000_000_000, :nanoseconds)
                },
                %{
                  rsi: Decimal.new(-0.030529013702074614),
                  datetime: DateTime.from_unix!(1_516_665_600_000_000_000, :nanoseconds)
                },
                %{
                  rsi: Decimal.new(-0.0239400614928722),
                  datetime: DateTime.from_unix!(1_516_752_000_000_000_000, :nanoseconds)
                }
              ]}
  end

  test "fetch price_volume_diff", context do
    mock(
      HTTPoison,
      :get,
      {:ok,
       %HTTPoison.Response{
         body:
           "[{\"price_volume_diff\": 0.0, \"timestamp\": 1516406400000000000}, {\"price_volume_diff\": -0.014954423076923185, \"timestamp\": 1516492800000000000}, {\"price_volume_diff\": -0.02373337292856359, \"timestamp\": 1516579200000000000}, {\"price_volume_diff\": -0.030529013702074614, \"timestamp\": 1516665600000000000}, {\"price_volume_diff\": -0.0239400614928722, \"timestamp\": 1516752000000000000}]",
         status_code: 200
       }}
    )

    result =
      TechIndicators.price_volume_diff(
        "XYZ",
        "USD",
        DateTime.from_unix!(1_516_406_400_000_000_000, :nanoseconds),
        DateTime.from_unix!(1_516_752_000_000_000_000, :nanoseconds),
        "1d"
      )

    assert result ==
             {:ok,
              [
                %{
                  price_volume_diff: Decimal.new(0.0),
                  datetime: DateTime.from_unix!(1_516_406_400_000_000_000, :nanoseconds)
                },
                %{
                  price_volume_diff: Decimal.new(-0.014954423076923185),
                  datetime: DateTime.from_unix!(1_516_492_800_000_000_000, :nanoseconds)
                },
                %{
                  price_volume_diff: Decimal.new(-0.02373337292856359),
                  datetime: DateTime.from_unix!(1_516_579_200_000_000_000, :nanoseconds)
                },
                %{
                  price_volume_diff: Decimal.new(-0.030529013702074614),
                  datetime: DateTime.from_unix!(1_516_665_600_000_000_000, :nanoseconds)
                },
                %{
                  price_volume_diff: Decimal.new(-0.0239400614928722),
                  datetime: DateTime.from_unix!(1_516_752_000_000_000_000, :nanoseconds)
                }
              ]}
  end
end
