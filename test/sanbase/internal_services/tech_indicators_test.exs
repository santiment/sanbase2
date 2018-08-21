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

  describe "erc20_exchange_funds_flow/2" do
    test "response: success" do
      mock(
        HTTPoison,
        :get,
        {:ok,
         %HTTPoison.Response{
           body: "[
            {
            \"ticker\": \"STX\",
            \"contract\": \"0x006bea43baa3f7a6f765f14f10a1a1b08334ef45\",
            \"exchange_in\": 42137.943511261336,
            \"exchange_out\": 47491.03261707162,
            \"exchange_diff\": -5353.089105810286,
            \"exchange_in_usd\": 19999.508713678784,
            \"exchange_out_usd\": 27016.56829841614,
            \"exchange_diff_usd\": -7017.059584737355,
            \"percent_diff_exchange_diff_usd\": -53.544923780744554,
            \"exchange_volume_usd\": 47016.077012094924,
            \"percent_diff_exchange_volume_usd\": 8.992750195374136,
            \"exchange_in_btc\": 2.226105762979626,
            \"exchange_out_btc\": 2.917965271091206,
            \"exchange_diff_btc\": -0.6918595081115799,
            \"percent_diff_exchange_diff_btc\": -37.732414353380335,
            \"exchange_volume_btc\": 5.144071034070832,
            \"percent_diff_exchange_volume_btc\": -6.591777042137359
            },
            {
            \"ticker\": \"STU\",
            \"contract\": \"0x0371a82e4a9d0a4312f3ee2ac9c6958512891372\",
            \"exchange_in\": 31202.667192279605,
            \"exchange_out\": 51137.30413164321,
            \"exchange_diff\": -19934.63693936361,
            \"exchange_in_usd\": 705.5825770771784,
            \"exchange_out_usd\": 1142.8535568866448,
            \"exchange_diff_usd\": -437.27097980946644,
            \"percent_diff_exchange_diff_usd\": -1082.6656035035915,
            \"exchange_volume_usd\": 1848.436133963823,
            \"percent_diff_exchange_volume_usd\": -670.2195106990696,
            \"exchange_in_btc\": 0.07827029805391122,
            \"exchange_out_btc\": 0.12840416783882946,
            \"exchange_diff_btc\": -0.05013386978491824,
            \"percent_diff_exchange_diff_btc\": -1017.1207858307316,
            \"exchange_volume_btc\": 0.2066744658927407,
            \"percent_diff_exchange_volume_btc\": -718.0463807486702
            }
          ]",
           status_code: 200
         }}
      )

      result =
        TechIndicators.erc20_exchange_funds_flow(
          DateTime.from_unix!(1_516_406_400),
          DateTime.from_unix!(1_516_492_800)
        )

      assert result ==
               {:ok,
                [
                  %{
                    ticker: "STX",
                    contract: "0x006bea43baa3f7a6f765f14f10a1a1b08334ef45",
                    exchange_in: 42137.943511261336,
                    exchange_out: 47491.03261707162,
                    exchange_diff: -5353.089105810286,
                    exchange_in_usd: 19999.508713678784,
                    exchange_out_usd: 27016.56829841614,
                    exchange_diff_usd: -7017.059584737355,
                    percent_diff_exchange_diff_usd: -53.544923780744554,
                    exchange_volume_usd: 47016.077012094924,
                    percent_diff_exchange_volume_usd: 8.992750195374136,
                    exchange_in_btc: 2.226105762979626,
                    exchange_out_btc: 2.917965271091206,
                    exchange_diff_btc: -0.6918595081115799,
                    percent_diff_exchange_diff_btc: -37.732414353380335,
                    exchange_volume_btc: 5.144071034070832,
                    percent_diff_exchange_volume_btc: -6.591777042137359
                  },
                  %{
                    ticker: "STU",
                    contract: "0x0371a82e4a9d0a4312f3ee2ac9c6958512891372",
                    exchange_in: 31202.667192279605,
                    exchange_out: 51137.30413164321,
                    exchange_diff: -19934.63693936361,
                    exchange_in_usd: 705.5825770771784,
                    exchange_out_usd: 1142.8535568866448,
                    exchange_diff_usd: -437.27097980946644,
                    percent_diff_exchange_diff_usd: -1082.6656035035915,
                    exchange_volume_usd: 1848.436133963823,
                    percent_diff_exchange_volume_usd: -670.2195106990696,
                    exchange_in_btc: 0.07827029805391122,
                    exchange_out_btc: 0.12840416783882946,
                    exchange_diff_btc: -0.05013386978491824,
                    percent_diff_exchange_diff_btc: -1017.1207858307316,
                    exchange_volume_btc: 0.2066744658927407,
                    percent_diff_exchange_volume_btc: -718.0463807486702
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
        TechIndicators.erc20_exchange_funds_flow(
          DateTime.from_unix!(1_516_406_400),
          DateTime.from_unix!(1_516_492_800)
        )
      end

      assert capture_log(result) =~
               "Error status 404 fetching erc20 exchange funds flow: Some message\n"
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
        TechIndicators.erc20_exchange_funds_flow(
          DateTime.from_unix!(1_516_406_400),
          DateTime.from_unix!(1_516_492_800)
        )
      end

      assert capture_log(result) =~ "Cannot fetch erc20 exchange funds flow data: :econnrefused\n"
    end
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
          "santiment",
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
          "santiment",
          DateTime.from_unix!(1_523_876_400),
          DateTime.from_unix!(1_523_880_000),
          "1h",
          :telegram_discussion_overview
        )
      end

      assert capture_log(result) =~
               "Error status 404 fetching social volume for project santiment: Some message\n"
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
          "santiment",
          DateTime.from_unix!(1_523_876_400),
          DateTime.from_unix!(1_523_880_000),
          "1h",
          :telegram_discussion_overview
        )
      end

      assert capture_log(result) =~
               "Cannot fetch social volume data for project santiment: :econnrefused\n"
    end
  end

  describe "social_volume_projects/0" do
    test "response: success" do
      mock(
        HTTPoison,
        :get,
        {:ok,
         %HTTPoison.Response{
           body:
             "[\"ADA_cardano\", \"BCH_bitcoin-cash\", \"BTC_bitcoin\", \"DRGN_dragonchain\", \"EOS_eos\"]",
           status_code: 200
         }}
      )

      result = TechIndicators.social_volume_projects()

      assert result == {:ok, ["cardano", "bitcoin-cash", "bitcoin", "dragonchain", "eos"]}
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

      result = fn -> TechIndicators.social_volume_projects() end

      assert capture_log(result) =~
               "Error status 404 fetching social volume projects: Some message\n"
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

      result = fn -> TechIndicators.social_volume_projects() end

      assert capture_log(result) =~ "Cannot fetch social volume projects data: :econnrefused\n"
    end
  end

  describe "topic_search/5" do
    test "response: success" do
      from = 1_533_114_000
      to = 1_534_323_600

      mock(
        HTTPoison,
        :get,
        {:ok,
         %HTTPoison.Response{
           body:
             "{\"messages\": {\"telegram\": [{\"text\": \"BTC moon\", \"timestamp\": 1533307652}, {\"text\": \"0.1c of usd won't make btc moon, you realize that?\", \"timestamp\": 1533694150}], \"professional_traders_chat\": [{\"text\": \"ow ... yea ... after btc moon and u become rich u mean ::D:\", \"timestamp\": 1533373739}, {\"text\": \"Next btc moon\", \"timestamp\": 1533741643}]}, \"charts_data\": {\"telegram\": [{\"mentions_count\": 1, \"timestamp\": 1533146400}, {\"mentions_count\": 0, \"timestamp\": 1533168000}], \"professional_traders_chat\": [{\"mentions_count\": 1, \"timestamp\": 1533362400}, {\"mentions_count\": 1, \"timestamp\": 1533384000}]}}",
           status_code: 200
         }}
      )

      result =
        TechIndicators.topic_search(
          [:telegram, :professional_traders_chat],
          "btc moon",
          DateTime.from_unix!(from),
          DateTime.from_unix!(to),
          "6h"
        )

      assert result ==
               {:ok,
                %{
                  charts_data: %{
                    telegram: [
                      %{datetime: DateTime.from_unix!(1_533_146_400), mentions_count: 1},
                      %{datetime: DateTime.from_unix!(1_533_168_000), mentions_count: 0}
                    ],
                    professional_traders_chat: [
                      %{datetime: DateTime.from_unix!(1_533_362_400), mentions_count: 1},
                      %{datetime: DateTime.from_unix!(1_533_384_000), mentions_count: 1}
                    ]
                  },
                  messages: %{
                    telegram: [
                      %{datetime: DateTime.from_unix!(1_533_307_652), text: "BTC moon"},
                      %{
                        datetime: DateTime.from_unix!(1_533_694_150),
                        text: "0.1c of usd won't make btc moon, you realize that?"
                      }
                    ],
                    professional_traders_chat: [
                      %{
                        datetime: DateTime.from_unix!(1_533_373_739),
                        text: "ow ... yea ... after btc moon and u become rich u mean ::D:"
                      },
                      %{datetime: DateTime.from_unix!(1_533_741_643), text: "Next btc moon"}
                    ]
                  }
                }}
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
        TechIndicators.topic_search(
          [:telegram, :professional_traders_chat],
          "btc moon",
          DateTime.from_unix!(1_533_114_000),
          DateTime.from_unix!(1_534_323_600),
          "6h"
        )
      end

      assert capture_log(result) =~
               "Error status 404 fetching results for search text \"btc moon\": Some message\n"
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
        TechIndicators.topic_search(
          [:telegram, :professional_traders_chat],
          "btc moon",
          DateTime.from_unix!(1_533_114_000),
          DateTime.from_unix!(1_534_323_600),
          "6h"
        )
      end

      assert capture_log(result) =~
               "Cannot fetch results for search text \"btc moon\": :econnrefused\n"
    end
  end
end
