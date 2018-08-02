defmodule Sanbase.InternalServices.TechIndicatorsTest do
  use SanbaseWeb.ConnCase, async: false

  import Mockery
  import ExUnit.CaptureLog

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
                  macd: 0.0,
                  datetime: DateTime.from_unix!(1_516_406_400)
                },
                %{
                  macd: -0.014954423076923185,
                  datetime: DateTime.from_unix!(1_516_492_800)
                },
                %{
                  macd: -0.02373337292856359,
                  datetime: DateTime.from_unix!(1_516_579_200)
                },
                %{
                  macd: -0.030529013702074614,
                  datetime: DateTime.from_unix!(1_516_665_600)
                },
                %{
                  macd: -0.0239400614928722,
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
                  rsi: 0.0,
                  datetime: DateTime.from_unix!(1_516_406_400)
                },
                %{
                  rsi: -0.014954423076923185,
                  datetime: DateTime.from_unix!(1_516_492_800)
                },
                %{
                  rsi: -0.02373337292856359,
                  datetime: DateTime.from_unix!(1_516_579_200)
                },
                %{
                  rsi: -0.030529013702074614,
                  datetime: DateTime.from_unix!(1_516_665_600)
                },
                %{
                  rsi: -0.0239400614928722,
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
        "bohman",
        14,
        7
      )

    assert result ==
             {:ok,
              [
                %{
                  price_volume_diff: 0.0,
                  price_change: 0.04862261825993345,
                  volume_change: 0.030695260272520467,
                  datetime: DateTime.from_unix!(1_516_406_400)
                },
                %{
                  price_volume_diff: -0.014954423076923185,
                  price_change: 0.04862261825993345,
                  volume_change: 0.030695260272520467,
                  datetime: DateTime.from_unix!(1_516_492_800)
                },
                %{
                  price_volume_diff: -0.02373337292856359,
                  price_change: 0.04862261825993345,
                  volume_change: 0.030695260272520467,
                  datetime: DateTime.from_unix!(1_516_579_200)
                },
                %{
                  price_volume_diff: -0.030529013702074614,
                  price_change: 0.04862261825993345,
                  volume_change: 0.030695260272520467,
                  datetime: DateTime.from_unix!(1_516_665_600)
                },
                %{
                  price_volume_diff: -0.0239400614928722,
                  price_change: 0.04862261825993345,
                  volume_change: 0.030695260272520467,
                  datetime: DateTime.from_unix!(1_516_752_000)
                }
              ]}
  end

  test "fetch twitter mention count", _context do
    mock(
      HTTPoison,
      :get,
      {:ok,
       %HTTPoison.Response{
         body:
           "[{\"mention_count\": 0, \"timestamp\": 1516406400}, {\"mention_count\": 1234, \"timestamp\": 1516492800}]",
         status_code: 200
       }}
    )

    result =
      TechIndicators.twitter_mention_count(
        "XYZ",
        DateTime.from_unix!(1_516_406_400),
        DateTime.from_unix!(1_516_492_800),
        "1d"
      )

    assert result ==
             {:ok,
              [
                %{
                  mention_count: 0,
                  datetime: DateTime.from_unix!(1_516_406_400)
                },
                %{
                  mention_count: 1234,
                  datetime: DateTime.from_unix!(1_516_492_800)
                }
              ]}
  end

  test "fetch emojis_sentiment", _context do
    mock(
      HTTPoison,
      :get,
      {:ok,
       %HTTPoison.Response{
         body:
           "[{\"sentiment\": 0, \"timestamp\": 1516406400}, {\"sentiment\": 1234, \"timestamp\": 1516492800}]",
         status_code: 200
       }}
    )

    result =
      TechIndicators.emojis_sentiment(
        DateTime.from_unix!(1_516_406_400),
        DateTime.from_unix!(1_516_492_800),
        "1d"
      )

    assert result ==
             {:ok,
              [
                %{
                  sentiment: 0,
                  datetime: DateTime.from_unix!(1_516_406_400)
                },
                %{
                  sentiment: 1234,
                  datetime: DateTime.from_unix!(1_516_492_800)
                }
              ]}
  end

  describe "social_volume/5" do
    test "response: success" do
      from = 1_523_876_400
      to = 1_523_880_000

      mock(
        HTTPoison,
        :get,
        {:ok,
         %HTTPoison.Response{
           body:
             "[{\"mentions_count\": 5, \"timestamp\": 1523876400}, {\"mentions_count\": 15, \"timestamp\": 1523880000}]",
           status_code: 200
         }}
      )

      result =
        TechIndicators.social_volume(
          "Foo",
          DateTime.from_unix!(from),
          DateTime.from_unix!(to),
          "1h",
          :telegram_discussion_overview
        )

      assert result ==
               {:ok,
                [
                  %{
                    mentions_count: 5,
                    datetime: DateTime.from_unix!(from)
                  },
                  %{
                    mentions_count: 15,
                    datetime: DateTime.from_unix!(to)
                  }
                ]}
    end

    test "response: 404" do
      mock(
        HTTPoison,
        :get,
        {:ok,
         %HTTPoison.Response{
           body: "Some message",
           status_code: 404
         }}
      )

      result = fn ->
        TechIndicators.social_volume(
          "Foo",
          DateTime.from_unix!(1_523_876_400),
          DateTime.from_unix!(1_523_880_000),
          "1h",
          :telegram_discussion_overview
        )
      end

      assert capture_log(result) =~
               "Error status 404 fetching social volume for ticker Foo: Some message\n"
    end

    test "response: error" do
      mock(
        HTTPoison,
        :get,
        {:error,
         %HTTPoison.Error{
           reason: :econnrefused
         }}
      )

      result = fn ->
        TechIndicators.social_volume(
          "Foo",
          DateTime.from_unix!(1_523_876_400),
          DateTime.from_unix!(1_523_880_000),
          "1h",
          :telegram_discussion_overview
        )
      end

      assert capture_log(result) =~
               "Cannot fetch social volume data for ticker Foo: :econnrefused\n"
    end
  end

  describe "social_volume_tickers/0" do
    test "response: success" do
      mock(
        HTTPoison,
        :get,
        {:ok,
         %HTTPoison.Response{
           body: "[\"ADA\", \"BCH\", \"BTC\", \"DRGN\", \"EOS\"]",
           status_code: 200
         }}
      )

      result = TechIndicators.social_volume_tickers()

      assert result == {:ok, ["ADA", "BCH", "BTC", "DRGN", "EOS"]}
    end

    test "response: 404" do
      mock(
        HTTPoison,
        :get,
        {:ok,
         %HTTPoison.Response{
           body: "Some message",
           status_code: 404
         }}
      )

      result = fn -> TechIndicators.social_volume_tickers() end

      assert capture_log(result) =~
               "Error status 404 fetching social volume tickers: Some message\n"
    end

    test "response: error" do
      mock(
        HTTPoison,
        :get,
        {:error,
         %HTTPoison.Error{
           reason: :econnrefused
         }}
      )

      result = fn -> TechIndicators.social_volume_tickers() end

      assert capture_log(result) =~ "Cannot fetch social volume tickers data: :econnrefused\n"
    end
  end
end
