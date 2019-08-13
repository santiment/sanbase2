defmodule Sanbase.SocialData.TrendingWordsTest do
  use Sanbase.DataCase

  import Mock
  import Sanbase.DateTimeUtils, only: [from_iso8601_to_unix!: 1, from_iso8601!: 1]

  alias Sanbase.SocialData.TrendingWords

  setup do
    [
      dt1_str: "2019-01-01T00:00:00Z",
      dt2_str: "2019-01-02T00:00:00Z",
      dt3_str: "2019-01-03T00:00:00Z"
    ]
  end

  describe "get trending words for time interval" do
    test "clickhouse returns data", context do
      %{dt1_str: dt1_str, dt2_str: dt2_str, dt3_str: dt3_str} = context

      with_mock Sanbase.ClickhouseRepo,
        query: fn _, _ ->
          {:ok, %{rows: trending_words_rows(dt1_str, dt2_str, dt3_str)}}
        end do
        result = TrendingWords.get(from_iso8601!(dt1_str), from_iso8601!(dt3_str), "1d", 2)

        assert result ==
                 {:ok,
                  %{
                    from_iso8601!(dt1_str) => [
                      %{score: 5, word: "ethereum"},
                      %{score: 10, word: "bitcoin"}
                    ],
                    from_iso8601!(dt2_str) => [
                      %{score: 70, word: "boom"},
                      %{score: 2, word: "san"}
                    ],
                    from_iso8601!(dt3_str) => [
                      %{score: 2, word: "xrp"},
                      %{score: 1, word: "eth"}
                    ]
                  }}
      end
    end

    test "clickhouse returns error", context do
      %{dt1_str: dt1_str, dt3_str: dt3_str} = context

      with_mock Sanbase.ClickhouseRepo,
        query: fn _, _ -> {:error, "Something went wrong"} end do
        result = TrendingWords.get(from_iso8601!(dt1_str), from_iso8601!(dt3_str), "1d", 2)
        assert result == {:error, "Something went wrong"}
      end
    end
  end

  describe "get currently trending words" do
    test "clickhouse returns data", context do
      %{dt1_str: dt1_str, dt2_str: dt2_str, dt3_str: dt3_str} = context

      with_mock Sanbase.ClickhouseRepo,
        query: fn _, _ ->
          {:ok, %{rows: trending_words_rows(dt1_str, dt2_str, dt3_str)}}
        end do
        result = TrendingWords.get_trending_now()

        assert result == {:ok, [%{score: 2, word: "xrp"}, %{score: 1, word: "eth"}]}
      end
    end

    test "clickhouse returns error", _context do
      with_mock Sanbase.ClickhouseRepo,
        query: fn _, _ -> {:error, "Something went wrong"} end do
        result = TrendingWords.get_trending_now()

        assert result == {:error, "Something went wrong"}
      end
    end
  end

  describe "get word history stats" do
    test "clickhouse returns data", context do
      %{dt1_str: dt1_str, dt2_str: dt2_str, dt3_str: dt3_str} = context

      with_mock Sanbase.ClickhouseRepo,
        query: fn _, _ ->
          {:ok, %{rows: word_trending_history_rows(dt1_str, dt2_str, dt3_str)}}
        end do
        result =
          TrendingWords.get_word_stats(
            "word'",
            from_iso8601!(dt1_str),
            from_iso8601!(dt3_str),
            "1d",
            10
          )

        assert result ==
                 {:ok,
                  [
                    %{datetime: from_iso8601!(dt1_str), position: 10},
                    %{datetime: from_iso8601!(dt2_str), position: 1},
                    %{datetime: from_iso8601!(dt3_str), position: nil}
                  ]}
      end
    end

    test "clickhouse returns error", _context do
      with_mock Sanbase.ClickhouseRepo,
        query: fn _, _ -> {:error, "Something went wrong"} end do
        result = TrendingWords.get_trending_now()

        assert result == {:error, "Something went wrong"}
      end
    end
  end

  defp word_trending_history_rows(dt1_str, dt2_str, dt3_str) do
    [
      [from_iso8601_to_unix!(dt1_str), 10],
      [from_iso8601_to_unix!(dt2_str), 1],
      [from_iso8601_to_unix!(dt3_str), 0]
    ]
  end

  defp trending_words_rows(dt1_str, dt2_str, dt3_str) do
    [
      [from_iso8601_to_unix!(dt1_str), "bitcoin", 10],
      [from_iso8601_to_unix!(dt1_str), "ethereum", 5],
      [from_iso8601_to_unix!(dt2_str), "san", 2],
      [from_iso8601_to_unix!(dt2_str), "boom", 70],
      [from_iso8601_to_unix!(dt3_str), "eth", 1],
      [from_iso8601_to_unix!(dt3_str), "xrp", 2]
    ]
  end
end
