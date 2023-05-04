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
        result = TrendingWords.get_trending_words(dt1, dt3, "1d", 2)

        assert result ==
                 {:ok,
                  %{
                    dt1 => [
                      %{
                        score: 5,
                        word: "ethereum",
                        summaries: [%{datetime: dt1, source: "telegram", summary: "summary2"}]
                      },
                      %{
                        score: 10,
                        word: "bitcoin",
                        summaries: [%{datetime: dt1, source: "telegram", summary: "summary1"}]
                      }
                    ],
                    dt2 => [
                      %{
                        score: 70,
                        word: "boom",
                        summaries: [%{datetime: dt2, source: "telegram", summary: "summary4"}]
                      },
                      %{
                        score: 2,
                        word: "san",
                        summaries: [%{datetime: dt2, source: "telegram", summary: "summary3"}]
                      }
                    ],
                    dt3 => [
                      %{
                        score: 2,
                        word: "xrp",
                        summaries: [%{datetime: dt3, source: "telegram", summary: "summary6"}]
                      },
                      %{
                        score: 1,
                        word: "eth",
                        summaries: [%{datetime: dt3, source: "reddit", summary: "summary5"}]
                      }
                    ]
                  }}
      end)
    end

    test "clickhouse returns error", context do
      %{dt1: dt1, dt3: dt3} = context

      Sanbase.Mock.prepare_mock2(&Sanbase.ClickhouseRepo.query/2, {:error, "error"})
      |> Sanbase.Mock.run_with_mocks(fn ->
        {:error, error} = TrendingWords.get_trending_words(dt1, dt3, "1d", 2)

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
        result = TrendingWords.get_currently_trending_words(10)

        assert result ==
                 {:ok,
                  [
                    %{
                      score: 2,
                      word: "xrp",
                      summaries: [%{datetime: dt3, source: "telegram", summary: "summary6"}]
                    },
                    %{
                      score: 1,
                      word: "eth",
                      summaries: [%{datetime: dt3, source: "reddit", summary: "summary5"}]
                    }
                  ]}
      end)
    end

    test "clickhouse returns error", _context do
      Sanbase.Mock.prepare_mock2(&Sanbase.ClickhouseRepo.query/2, {:error, "error"})
      |> Sanbase.Mock.run_with_mocks(fn ->
        {:error, error} = TrendingWords.get_currently_trending_words(10)

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
        result = TrendingWords.get_word_trending_history("word", dt1, dt3, "1d", 10)

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
        {:error, error} = TrendingWords.get_word_trending_history("word", dt1, dt2, "1h", 10)

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
        result = TrendingWords.get_project_trending_history(project.slug, dt1, dt3, "1d", 10)

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
          TrendingWords.get_project_trending_history(project.slug, dt1, dt2, "1h", 10)

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

    [
      [dt1_unix, "bitcoin", nil, 10, [["telegram", dt1_unix, "summary1"]]],
      [dt1_unix, "ethereum", nil, 5, [["telegram", dt1_unix, "summary2"]]],
      [dt2_unix, "san", nil, 2, [["telegram", dt2_unix, "summary3"]]],
      [dt2_unix, "boom", nil, 70, [["telegram", dt2_unix, "summary4"]]],
      [dt3_unix, "eth", nil, 1, [["reddit", dt3_unix, "summary5"]]],
      [dt3_unix, "xrp", nil, 2, [["telegram", dt3_unix, "summary6"]]]
    ]
  end
end
