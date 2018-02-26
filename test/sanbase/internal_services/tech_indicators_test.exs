defmodule Sanbase.InternalServices.TechIndicatorsTest do
  use SanbaseWeb.ConnCase
  use Phoenix.ConnTest

  import Mockery

  alias Sanbase.InternalServices.TechIndicators

  test "fetch macd", _context do
    mock(
      HTTPoison,
      :get,
      {:ok,
       %HTTPoison.Response{
         body:
           "[{\"macd\": 0.0, \"timestamp\": 1516406400}, {\"macd\": -0.014954423076923185, \"timestamp\": 1516492800}, {\"macd\": -0.02373337292856359, \"timestamp\": 1516579200}, {\"macd\": -0.030529013702074614, \"timestamp\": 1516665600}, {\"macd\": -0.0239400614928722, \"timestamp\": 1516752000}]",
         status_code: 200
       }}
    )

    result =
      TechIndicators.macd(
        "XYZ",
        "USD",
        DateTime.from_unix!(1_516_406_400),
        DateTime.from_unix!(1_516_752_000),
        "1d"
      )

    assert result ==
             {:ok,
              [
                %{
                  macd: Decimal.new(0.0),
                  datetime: DateTime.from_unix!(1_516_406_400)
                },
                %{
                  macd: Decimal.new(-0.014954423076923185),
                  datetime: DateTime.from_unix!(1_516_492_800)
                },
                %{
                  macd: Decimal.new(-0.02373337292856359),
                  datetime: DateTime.from_unix!(1_516_579_200)
                },
                %{
                  macd: Decimal.new(-0.030529013702074614),
                  datetime: DateTime.from_unix!(1_516_665_600)
                },
                %{
                  macd: Decimal.new(-0.0239400614928722),
                  datetime: DateTime.from_unix!(1_516_752_000)
                }
              ]}
  end

  test "fetch rsi", _context do
    mock(
      HTTPoison,
      :get,
      {:ok,
       %HTTPoison.Response{
         body:
           "[{\"rsi\": 0.0, \"timestamp\": 1516406400}, {\"rsi\": -0.014954423076923185, \"timestamp\": 1516492800}, {\"rsi\": -0.02373337292856359, \"timestamp\": 1516579200}, {\"rsi\": -0.030529013702074614, \"timestamp\": 1516665600}, {\"rsi\": -0.0239400614928722, \"timestamp\": 1516752000}]",
         status_code: 200
       }}
    )

    result =
      TechIndicators.rsi(
        "XYZ",
        "USD",
        DateTime.from_unix!(1_516_406_400),
        DateTime.from_unix!(1_516_752_000),
        "1d",
        5
      )

    assert result ==
             {:ok,
              [
                %{
                  rsi: Decimal.new(0.0),
                  datetime: DateTime.from_unix!(1_516_406_400)
                },
                %{
                  rsi: Decimal.new(-0.014954423076923185),
                  datetime: DateTime.from_unix!(1_516_492_800)
                },
                %{
                  rsi: Decimal.new(-0.02373337292856359),
                  datetime: DateTime.from_unix!(1_516_579_200)
                },
                %{
                  rsi: Decimal.new(-0.030529013702074614),
                  datetime: DateTime.from_unix!(1_516_665_600)
                },
                %{
                  rsi: Decimal.new(-0.0239400614928722),
                  datetime: DateTime.from_unix!(1_516_752_000)
                }
              ]}
  end

  test "fetch price_volume_diff", _context do
    mock(
      HTTPoison,
      :get,
      {:ok,
       %HTTPoison.Response{
         body:
           "[{\"price_volume_diff\": 0.0, \"price_change\": 0.04862261825993345, \"volume_change\": 0.030695260272520467, \"timestamp\": 1516406400}, {\"price_volume_diff\": -0.014954423076923185, \"price_change\": 0.04862261825993345, \"volume_change\": 0.030695260272520467, \"timestamp\": 1516492800}, {\"price_volume_diff\": -0.02373337292856359, \"price_change\": 0.04862261825993345, \"volume_change\": 0.030695260272520467, \"timestamp\": 1516579200}, {\"price_volume_diff\": -0.030529013702074614, \"price_change\": 0.04862261825993345, \"volume_change\": 0.030695260272520467, \"timestamp\": 1516665600}, {\"price_volume_diff\": -0.0239400614928722, \"price_change\": 0.04862261825993345, \"volume_change\": 0.030695260272520467, \"timestamp\": 1516752000}]",
         status_code: 200
       }}
    )

    result =
      TechIndicators.price_volume_diff_ma(
        "XYZ",
        "USD",
        DateTime.from_unix!(1_516_406_400),
        DateTime.from_unix!(1_516_752_000),
        "1d",
        14,
        7
      )

    assert result ==
             {:ok,
              [
                %{
                  price_volume_diff: Decimal.new(0.0),
                  price_change: Decimal.new(0.04862261825993345),
                  volume_change: Decimal.new(0.030695260272520467),
                  datetime: DateTime.from_unix!(1_516_406_400)
                },
                %{
                  price_volume_diff: Decimal.new(-0.014954423076923185),
                  price_change: Decimal.new(0.04862261825993345),
                  volume_change: Decimal.new(0.030695260272520467),
                  datetime: DateTime.from_unix!(1_516_492_800)
                },
                %{
                  price_volume_diff: Decimal.new(-0.02373337292856359),
                  price_change: Decimal.new(0.04862261825993345),
                  volume_change: Decimal.new(0.030695260272520467),
                  datetime: DateTime.from_unix!(1_516_579_200)
                },
                %{
                  price_volume_diff: Decimal.new(-0.030529013702074614),
                  price_change: Decimal.new(0.04862261825993345),
                  volume_change: Decimal.new(0.030695260272520467),
                  datetime: DateTime.from_unix!(1_516_665_600)
                },
                %{
                  price_volume_diff: Decimal.new(-0.0239400614928722),
                  price_change: Decimal.new(0.04862261825993345),
                  volume_change: Decimal.new(0.030695260272520467),
                  datetime: DateTime.from_unix!(1_516_752_000)
                }
              ]}
  end
end
