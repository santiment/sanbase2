defmodule Sanbase.SocialData.TrendingWordsTest do
  use Sanbase.DataCase

  import Sanbase.Factory

  alias Sanbase.SocialData.TrendingWords

  @moduletag capture_log: true

  setup do
    [
      dt1: ~U[2019-01-01 00:00:00Z],
      dt2: ~U[2019-01-02 00:00:00Z],
      dt3: ~U[2019-01-03 00:00:00Z]
    ]
  end

  describe "get trending words for time interval" do
    test "clickhouse returns data", context do
      %{dt1: dt1, dt2: dt2, dt3: dt3} = context
      rows = trending_words_rows(dt1, dt2, dt3)

      Sanbase.Mock.prepare_mock2(&Sanbase.ClickhouseRepo.query/2, {:ok, %{rows: rows}})
      |> Sanbase.Mock.run_with_mocks(fn ->
        result = TrendingWords.get_trending_words(dt1, dt3, "1d", 2, :all)

        assert result ==
                 {
                   :ok,
                   %{
                     dt1 => [
                       %{
                         context: [%{score: 1.0, word: "usd"}, %{score: 0.5, word: "money"}],
                         score: 5,
                         slug: "ethereum",
                         summaries: [
                           %{
                             datetime: dt1,
                             source: "4chan,reddit",
                             summary: "summary2"
                           }
                         ],
                         summary: "summary2",
                         word: "ethereum",
                         negative_sentiment_ratio: 0.3,
                         neutral_sentiment_ratio: 0.5,
                         positive_sentiment_ratio: 0.2,
                         bearish_bb_sentiment_ratio: 0.3,
                         neutral_bb_sentiment_ratio: 0.5,
                         bullish_bb_sentiment_ratio: 0.2
                       },
                       %{
                         context: [%{score: 1.0, word: "usd"}, %{score: 0.5, word: "money"}],
                         score: 10,
                         slug: "bitcoin",
                         summaries: [
                           %{
                             datetime: dt1,
                             source: "4chan,reddit",
                             summary: "summary1"
                           }
                         ],
                         summary: "summary1",
                         word: "bitcoin",
                         negative_sentiment_ratio: 0.3,
                         neutral_sentiment_ratio: 0.5,
                         positive_sentiment_ratio: 0.2,
                         bearish_bb_sentiment_ratio: 0.3,
                         neutral_bb_sentiment_ratio: 0.5,
                         bullish_bb_sentiment_ratio: 0.2
                       }
                     ],
                     dt2 => [
                       %{
                         context: [%{score: 1.0, word: "usd"}, %{score: 0.5, word: "money"}],
                         score: 70,
                         slug: nil,
                         summaries: [
                           %{
                             datetime: dt2,
                             source: "4chan,reddit",
                             summary: "summary4"
                           }
                         ],
                         summary: "summary4",
                         word: "boom",
                         negative_sentiment_ratio: 0.1,
                         neutral_sentiment_ratio: 0.7,
                         positive_sentiment_ratio: 0.2,
                         bearish_bb_sentiment_ratio: 0.1,
                         neutral_bb_sentiment_ratio: 0.7,
                         bullish_bb_sentiment_ratio: 0.2
                       },
                       %{
                         context: [%{score: 1.0, word: "usd"}, %{score: 0.5, word: "money"}],
                         score: 2,
                         slug: "santiment",
                         summaries: [
                           %{
                             datetime: dt2,
                             source: "4chan,reddit",
                             summary: "summary3"
                           }
                         ],
                         summary: "summary3",
                         word: "san",
                         negative_sentiment_ratio: 0.1,
                         neutral_sentiment_ratio: 0.5,
                         positive_sentiment_ratio: 0.4,
                         bearish_bb_sentiment_ratio: 0.1,
                         neutral_bb_sentiment_ratio: 0.5,
                         bullish_bb_sentiment_ratio: 0.4
                       }
                     ],
                     dt3 => [
                       %{
                         context: [%{score: 1.0, word: "usd"}, %{score: 0.5, word: "money"}],
                         score: 2,
                         slug: "ripple",
                         summaries: [
                           %{
                             datetime: dt3,
                             source: "4chan,reddit",
                             summary: "summary6"
                           }
                         ],
                         summary: "summary6",
                         word: "xrp",
                         negative_sentiment_ratio: 0.3,
                         neutral_sentiment_ratio: 0.5,
                         positive_sentiment_ratio: 0.2,
                         bearish_bb_sentiment_ratio: 0.3,
                         neutral_bb_sentiment_ratio: 0.5,
                         bullish_bb_sentiment_ratio: 0.2
                       },
                       %{
                         context: [%{score: 1.0, word: "usd"}, %{score: 0.5, word: "money"}],
                         score: 1,
                         slug: "ethereum",
                         summaries: [
                           %{
                             datetime: dt3,
                             source: "4chan,reddit",
                             summary: "summary5"
                           }
                         ],
                         summary: "summary5",
                         word: "eth",
                         negative_sentiment_ratio: 0.3,
                         neutral_sentiment_ratio: 0.5,
                         positive_sentiment_ratio: 0.2,
                         bearish_bb_sentiment_ratio: 0.3,
                         neutral_bb_sentiment_ratio: 0.5,
                         bullish_bb_sentiment_ratio: 0.2
                       }
                     ]
                   }
                 }
      end)
    end

    test "clickhouse returns error", context do
      %{dt1: dt1, dt3: dt3} = context

      Sanbase.Mock.prepare_mock2(&Sanbase.ClickhouseRepo.query/2, {:error, "error"})
      |> Sanbase.Mock.run_with_mocks(fn ->
        {:error, error} = TrendingWords.get_trending_words(dt1, dt3, "1d", 2, :all)

        assert error =~ "Cannot execute database query."
      end)
    end
  end

  describe "get currently trending words" do
    test "clickhouse returns data", context do
      %{dt1: dt1, dt2: dt2, dt3: dt3} = context
      rows = trending_words_rows(dt1, dt2, dt3)

      Sanbase.Mock.prepare_mock2(&Sanbase.ClickhouseRepo.query/2, {:ok, %{rows: rows}})
      |> Sanbase.Mock.run_with_mocks(fn ->
        result = TrendingWords.get_currently_trending_words(10, :all)

        assert result ==
                 {
                   :ok,
                   [
                     %{
                       context: [%{score: 1.0, word: "usd"}, %{score: 0.5, word: "money"}],
                       score: 2,
                       slug: "ripple",
                       summaries: [
                         %{
                           datetime: ~U[2019-01-03 00:00:00Z],
                           source: "4chan,reddit",
                           summary: "summary6"
                         }
                       ],
                       summary: "summary6",
                       word: "xrp",
                       negative_sentiment_ratio: 0.3,
                       neutral_sentiment_ratio: 0.5,
                       positive_sentiment_ratio: 0.2,
                       bearish_bb_sentiment_ratio: 0.3,
                       neutral_bb_sentiment_ratio: 0.5,
                       bullish_bb_sentiment_ratio: 0.2
                     },
                     %{
                       context: [%{score: 1.0, word: "usd"}, %{score: 0.5, word: "money"}],
                       score: 1,
                       slug: "ethereum",
                       summaries: [
                         %{
                           datetime: ~U[2019-01-03 00:00:00Z],
                           source: "4chan,reddit",
                           summary: "summary5"
                         }
                       ],
                       summary: "summary5",
                       word: "eth",
                       negative_sentiment_ratio: 0.3,
                       neutral_sentiment_ratio: 0.5,
                       positive_sentiment_ratio: 0.2,
                       bearish_bb_sentiment_ratio: 0.3,
                       neutral_bb_sentiment_ratio: 0.5,
                       bullish_bb_sentiment_ratio: 0.2
                     }
                   ]
                 }
      end)
    end

    test "clickhouse returns error", _context do
      Sanbase.Mock.prepare_mock2(&Sanbase.ClickhouseRepo.query/2, {:error, "error"})
      |> Sanbase.Mock.run_with_mocks(fn ->
        {:error, error} = TrendingWords.get_currently_trending_words(10, :all)

        assert error =~ "Cannot execute database query."
      end)
    end
  end

  describe "get word trending history stats" do
    test "clickhouse returns data", context do
      %{dt1: dt1, dt2: dt2, dt3: dt3} = context
      rows = word_trending_history_rows(dt1, dt2, dt3)

      Sanbase.Mock.prepare_mock2(&Sanbase.ClickhouseRepo.query/2, {:ok, %{rows: rows}})
      |> Sanbase.Mock.run_with_mocks(fn ->
        result = TrendingWords.get_word_trending_history("word", dt1, dt3, "1d", 10, :all)

        assert result ==
                 {:ok,
                  [
                    %{datetime: dt1, position: 10},
                    %{datetime: dt2, position: 1}
                  ]}
      end)
    end

    test "clickhouse returns error", context do
      %{dt1: dt1, dt2: dt2} = context

      Sanbase.Mock.prepare_mock2(&Sanbase.ClickhouseRepo.query/2, {:error, "error"})
      |> Sanbase.Mock.run_with_mocks(fn ->
        {:error, error} =
          TrendingWords.get_word_trending_history("word", dt1, dt2, "1h", 10, :all)

        assert error =~ "Cannot execute database query."
      end)
    end
  end

  describe "get project trending history stats" do
    test "clickhouse returns data", context do
      %{dt1: dt1, dt2: dt2, dt3: dt3} = context

      project = insert(:random_project)
      rows = project_trending_history_rows(dt1, dt2, dt3)

      Sanbase.Mock.prepare_mock2(&Sanbase.ClickhouseRepo.query/2, {:ok, %{rows: rows}})
      |> Sanbase.Mock.run_with_mocks(fn ->
        result =
          TrendingWords.get_project_trending_history(project.slug, dt1, dt3, "1d", 10, :all)

        assert result ==
                 {:ok,
                  [
                    %{datetime: dt1, position: 5},
                    %{datetime: dt3, position: 10}
                  ]}
      end)
    end

    test "clickhouse returns error", context do
      %{dt1: dt1, dt2: dt2} = context
      project = insert(:random_project)

      Sanbase.Mock.prepare_mock2(&Sanbase.ClickhouseRepo.query/2, {:error, "error"})
      |> Sanbase.Mock.run_with_mocks(fn ->
        {:error, error} =
          TrendingWords.get_project_trending_history(project.slug, dt1, dt2, "1h", 10, :all)

        assert error =~ "Cannot execute database query."
      end)
    end
  end

  defp word_trending_history_rows(dt1, dt2, dt3) do
    [
      [DateTime.to_unix(dt1), 10],
      [DateTime.to_unix(dt2), 1],
      [DateTime.to_unix(dt3), 0]
    ]
  end

  defp project_trending_history_rows(dt1, dt2, dt3) do
    [
      [DateTime.to_unix(dt1), 5],
      [DateTime.to_unix(dt2), 0],
      [DateTime.to_unix(dt3), 10]
    ]
  end

  defp trending_words_rows(dt1, dt2, dt3) do
    dt1_unix = DateTime.to_unix(dt1)
    dt2_unix = DateTime.to_unix(dt2)
    dt3_unix = DateTime.to_unix(dt3)

    context = [
      "{'word': 'usd', 'score': 1.0}",
      "{'word': 'money', 'score': 0.5}"
    ]

    [
      [
        dt1_unix,
        "bitcoin",
        "BTC_bitcoin",
        10,
        context,
        "summary1",
        [0.2, 0.3, 0.5],
        [0.2, 0.3, 0.5]
      ],
      [
        dt1_unix,
        "ethereum",
        "ETH_ethereum",
        5,
        context,
        "summary2",
        [0.2, 0.3, 0.5],
        [0.2, 0.3, 0.5]
      ],
      [
        dt2_unix,
        "san",
        "SAN_santiment",
        2,
        context,
        "summary3",
        [0.4, 0.1, 0.5],
        [0.4, 0.1, 0.5]
      ],
      [dt2_unix, "boom", nil, 70, context, "summary4", [0.2, 0.1, 0.7], [0.2, 0.1, 0.7]],
      [dt3_unix, "eth", "ETH_ethereum", 1, context, "summary5", [0.2, 0.3, 0.5], [0.2, 0.3, 0.5]],
      [dt3_unix, "xrp", "XRP_ripple", 2, context, "summary6", [0.2, 0.3, 0.5], [0.2, 0.3, 0.5]]
    ]
  end
end
