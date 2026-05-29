defmodule Sanbase.KnowledgeTest do
  use ExUnit.Case, async: true

  alias Sanbase.Knowledge

  defmodule ReverseStub do
    @behaviour Sanbase.Knowledge.Reranker
    @impl true
    def rerank(_query, candidates, _opts), do: {:ok, Enum.reverse(candidates)}
  end

  defmodule FailingStub do
    @behaviour Sanbase.Knowledge.Reranker
    @impl true
    def rerank(_query, _candidates, _opts), do: {:error, :boom}
  end

  describe "rerank_entries/4" do
    setup do
      entries = [
        %{title: "A", chunk: "alpha", similarity: 0.9, github_path: "a.md"},
        %{title: "B", chunk: "bravo", similarity: 0.7, github_path: "b.md"},
        %{title: "C", chunk: "charlie", similarity: 0.5, github_path: "c.md"}
      ]

      {:ok, entries: entries}
    end

    test "returns [] for empty entries" do
      assert Knowledge.rerank_entries("q", [], :academy) == []
    end

    test "returns the original entry maps re-ordered by the reranker", %{entries: entries} do
      result = Knowledge.rerank_entries("q", entries, :academy, reranker: ReverseStub)

      # The candidate normalization round-trips: callers get their input maps
      # back, only reordered.
      assert result == Enum.reverse(entries)
    end

    test "truncates to :top_n", %{entries: entries} do
      result = Knowledge.rerank_entries("q", entries, :academy, reranker: ReverseStub, top_n: 2)

      assert length(result) == 2
      assert Enum.map(result, & &1.title) == ["C", "B"]
    end

    test "falls back to input order (truncated) when the backend errors", %{entries: entries} do
      result = Knowledge.rerank_entries("q", entries, :academy, reranker: FailingStub, top_n: 2)

      assert Enum.map(result, & &1.title) == ["A", "B"]
    end
  end
end
