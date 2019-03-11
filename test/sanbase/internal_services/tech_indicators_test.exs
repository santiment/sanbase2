defmodule Sanbase.TechIndicatorsTest do
  use SanbaseWeb.ConnCase, async: false

  import Mockery
  import ExUnit.CaptureLog

  alias Sanbase.TechIndicators
  import Sanbase.Factory

  setup do
    project =
      insert(:project, %{
        coinmarketcap_id: "santiment",
        ticker: "SAN",
        main_contract_address: "0x123"
      })

    [
      project: project
    ]
  end

  test "fetch price_volume_diff", context do
    mock(
      HTTPoison,
      :get,
      {:ok,
       %HTTPoison.Response{
         body: """
         [
           #{Sanbase.TechIndicatorsTestResponse.price_volume_diff_prepend_response()},
           {
             "price_volume_diff": 0,
             "price_change": 0.04862261825993345,
             "volume_change": 0.030695260272520467,
             "timestamp": 1516406400
           },
           {
             "price_volume_diff": -0.014954423076923185,
             "price_change": 0.04862261825993345,
             "volume_change": 0.030695260272520467,
             "timestamp": 1516492800
           },
           {
             "price_volume_diff": -0.02373337292856359,
             "price_change": 0.04862261825993345,
             "volume_change": 0.030695260272520467,
             "timestamp": 1516579200
           },
           {
             "price_volume_diff": -0.030529013702074614,
             "price_change": 0.04862261825993345,
             "volume_change": 0.030695260272520467,
             "timestamp": 1516665600
           },
           {
             "price_volume_diff": -0.0239400614928722,
             "price_change": 0.04862261825993345,
             "volume_change": 0.030695260272520467,
             "timestamp": 1516752000
           }
         ]
         """,
         status_code: 200
       }}
    )

    result =
      TechIndicators.PriceVolumeDifference.price_volume_diff(
        context.project,
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

  test "fetch twitter mention count", context do
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
        context.project.ticker,
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
               "Error status 404 fetching social volume for project santiment"
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

      assert capture_log(result) =~ "Error status 404 fetching social volume projects"
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
             "{\"messages\": [{\"text\": \"BTC moon\", \"timestamp\": 1533307652}, {\"text\": \"0.1c of usd won't make btc moon, you realize that?\", \"timestamp\": 1533694150}], \"chart_data\": [{\"mentions_count\": 1, \"timestamp\": 1533146400}, {\"mentions_count\": 0, \"timestamp\": 1533168000}]}",
           status_code: 200
         }}
      )

      result =
        TechIndicators.topic_search(
          :telegram,
          "btc moon",
          DateTime.from_unix!(from),
          DateTime.from_unix!(to),
          "6h"
        )

      assert result ==
               {:ok,
                %{
                  chart_data: [
                    %{datetime: DateTime.from_unix!(1_533_146_400), mentions_count: 1},
                    %{datetime: DateTime.from_unix!(1_533_168_000), mentions_count: 0}
                  ],
                  messages: [
                    %{datetime: DateTime.from_unix!(1_533_307_652), text: "BTC moon"},
                    %{
                      datetime: DateTime.from_unix!(1_533_694_150),
                      text: "0.1c of usd won't make btc moon, you realize that?"
                    }
                  ]
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
          :telegram,
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
          :telegram,
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
