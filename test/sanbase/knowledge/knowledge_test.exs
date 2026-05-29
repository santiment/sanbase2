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
end
