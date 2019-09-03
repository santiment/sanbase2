defmodule Sanbase.SocialData.TrendingWordsTest do
  use Sanbase.DataCase

  import Mock
  import Sanbase.Factory
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
        result =
          TrendingWords.get_trending_words(
            from_iso8601!(dt1_str),
            from_iso8601!(dt3_str),
            "1d",
            2
          )

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
        result =
          TrendingWords.get_trending_words(
            from_iso8601!(dt1_str),
            from_iso8601!(dt3_str),
            "1d",
            2
          )

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
        result = TrendingWords.get_currently_trending_words()

        assert result == {:ok, [%{score: 2, word: "xrp"}, %{score: 1, word: "eth"}]}
      end
    end

    test "clickhouse returns error", _context do
      with_mock Sanbase.ClickhouseRepo,
        query: fn _, _ -> {:error, "Something went wrong"} end do
        result = TrendingWords.get_currently_trending_words()

        assert result == {:error, "Something went wrong"}
      end
    end
  end

  describe "get word trending history stats" do
    test "clickhouse returns data", context do
      %{dt1_str: dt1_str, dt2_str: dt2_str, dt3_str: dt3_str} = context

      with_mock Sanbase.ClickhouseRepo,
        query: fn _, _ ->
          {:ok, %{rows: word_trending_history_rows(dt1_str, dt2_str, dt3_str)}}
        end do
        result =
          TrendingWords.get_word_trending_history(
            "word",
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

    test "clickhouse returns error", context do
      %{dt1_str: dt1_str, dt2_str: dt2_str} = context

      with_mock Sanbase.ClickhouseRepo,
        query: fn _, _ -> {:error, "Something went wrong"} end do
        result =
          TrendingWords.get_word_trending_history(
            "word",
            from_iso8601!(dt1_str),
            from_iso8601!(dt2_str),
            "1h",
            10
          )

        assert result == {:error, "Something went wrong"}
      end
    end
  end

  describe "get project trending history stats" do
    test "clickhouse returns data", context do
      %{dt1_str: dt1_str, dt2_str: dt2_str, dt3_str: dt3_str} = context

      project = insert(:random_project)

      with_mock Sanbase.ClickhouseRepo,
        query: fn _, _ ->
          {:ok, %{rows: project_trending_history_rows(dt1_str, dt2_str, dt3_str)}}
        end do
        result =
          TrendingWords.get_project_trending_history(
            project.coinmarketcap_id,
            from_iso8601!(dt1_str),
            from_iso8601!(dt3_str),
            "1d",
            10
          )

        assert result ==
                 {:ok,
                  [
                    %{datetime: from_iso8601!(dt1_str), position: 5},
                    %{datetime: from_iso8601!(dt2_str), position: nil},
                    %{datetime: from_iso8601!(dt3_str), position: 10}
                  ]}
      end
    end

    test "clickhouse returns error", context do
      %{dt1_str: dt1_str, dt2_str: dt2_str} = context
      project = insert(:random_project)

      with_mock Sanbase.ClickhouseRepo,
        query: fn _, _ -> {:error, "Something went wrong"} end do
        result =
          TrendingWords.get_project_trending_history(
            project.coinmarketcap_id,
            from_iso8601!(dt1_str),
            from_iso8601!(dt2_str),
            "1h",
            10
          )

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

  defp project_trending_history_rows(dt1_str, dt2_str, dt3_str) do
    [
      [from_iso8601_to_unix!(dt1_str), 5],
      [from_iso8601_to_unix!(dt2_str), 0],
      [from_iso8601_to_unix!(dt3_str), 10]
    ]
  end

  defp trending_words_rows(dt1_str, dt2_str, dt3_str) do
    [
      [from_iso8601_to_unix!(dt1_str), "bitcoin", nil, 10],
      [from_iso8601_to_unix!(dt1_str), "ethereum", nil, 5],
      [from_iso8601_to_unix!(dt2_str), "san", nil, 2],
      [from_iso8601_to_unix!(dt2_str), "boom", nil, 70],
      [from_iso8601_to_unix!(dt3_str), "eth", nil, 1],
      [from_iso8601_to_unix!(dt3_str), "xrp", nil, 2]
    ]
  end
end
