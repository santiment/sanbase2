defmodule Sanbase.KnowledgeTest do
  use ExUnit.Case, async: true

  alias Sanbase.Knowledge

  defmodule ReverseStub do
    @behaviour Sanbase.Knowledge.Reranker
    @impl true
    def rerank(_query, candidates, _opts), do: {:ok, Enum.reverse(candidates)}
  end

  describe "rerank_entries/4" do
    # Empty input and error-fallback live in Reranker.call (see reranker_test.exs).
    # This guards the wrapper: callers get their original maps back, reordered,
    # and :top_n is forwarded through the to_candidates -> call -> map pipeline.
    test "round-trips the original entry maps, reordered and truncated to :top_n" do
      entries = [
        %{title: "A", chunk: "alpha", similarity: 0.9, github_path: "a.md"},
        %{title: "B", chunk: "bravo", similarity: 0.7, github_path: "b.md"},
        %{title: "C", chunk: "charlie", similarity: 0.5, github_path: "c.md"}
      ]

      result = Knowledge.rerank_entries("q", entries, :academy, reranker: ReverseStub, top_n: 2)

      assert result == [Enum.at(entries, 2), Enum.at(entries, 1)]
    end
  end

  describe "diversify_by_document/3" do
    defp hit(doc, idx), do: %{doc: doc, idx: idx}
    defp idxs(hits), do: Enum.map(hits, & &1.idx)

    test "round-robins distinct documents before backfilling later chunks" do
      # reranked order interleaves three documents; round 1 should surface one
      # chunk per document (a, b, c) before any second chunk is added.
      hits = [hit(:a, 1), hit(:a, 2), hit(:b, 3), hit(:a, 4), hit(:c, 5)]

      assert idxs(Knowledge.diversify_by_document(hits, & &1.doc, 5)) == [1, 3, 5, 2, 4]
    end

    test "maximises distinct documents when the limit is smaller than the candidates" do
      hits = [hit(:a, 1), hit(:a, 2), hit(:b, 3), hit(:a, 4), hit(:c, 5)]

      assert idxs(Knowledge.diversify_by_document(hits, & &1.doc, 3)) == [1, 3, 5]
    end

    test "backfills from a single document rather than under-filling the prompt" do
      hits = [hit(:a, 1), hit(:a, 2), hit(:a, 3)]

      assert idxs(Knowledge.diversify_by_document(hits, & &1.doc, 5)) == [1, 2, 3]
    end

    test "returns an empty list for no hits" do
      assert Knowledge.diversify_by_document([], & &1.doc, 5) == []
    end
  end
end
