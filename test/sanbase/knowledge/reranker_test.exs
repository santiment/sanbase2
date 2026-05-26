defmodule Sanbase.Knowledge.RerankerTest do
  use ExUnit.Case, async: true

  alias Sanbase.Knowledge.Reranker
  alias Sanbase.Knowledge.Reranker.Noop

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

  describe "Noop.rerank/3" do
    test "returns candidates in input order" do
      candidates = [
        %{id: 1, text: "a", similarity: 0.9},
        %{id: 2, text: "b", similarity: 0.5}
      ]

      assert {:ok, ^candidates} = Noop.rerank("q", candidates, [])
    end

    test "handles empty list" do
      assert {:ok, []} = Noop.rerank("q", [], [])
    end
  end

  describe "call/3" do
    setup do
      candidates = [
        %{id: 1, text: "a", similarity: 0.9},
        %{id: 2, text: "b", similarity: 0.7},
        %{id: 3, text: "c", similarity: 0.5}
      ]

      {:ok, candidates: candidates}
    end

    test "defaults to Noop when no reranker configured", %{candidates: candidates} do
      assert Reranker.call("q", candidates) == candidates
    end

    test "dispatches to configured reranker", %{candidates: candidates} do
      assert Reranker.call("q", candidates, reranker: ReverseStub) ==
               Enum.reverse(candidates)
    end

    test "truncates to top_n", %{candidates: candidates} do
      result = Reranker.call("q", candidates, reranker: ReverseStub, top_n: 2)
      assert length(result) == 2
      assert Enum.map(result, & &1.id) == [3, 2]
    end

    test "falls back to input order truncated when backend errors", %{candidates: candidates} do
      result = Reranker.call("q", candidates, reranker: FailingStub, top_n: 2)
      assert length(result) == 2
      assert Enum.map(result, & &1.id) == [1, 2]
    end

    test "top_n larger than list returns the full list", %{candidates: candidates} do
      result = Reranker.call("q", candidates, reranker: ReverseStub, top_n: 99)
      assert length(result) == length(candidates)
    end

    test "respects application env default when no :reranker opt given", %{
      candidates: candidates
    } do
      original = Application.get_env(:sanbase, Sanbase.Knowledge.Reranker)
      Application.put_env(:sanbase, Sanbase.Knowledge.Reranker, default: ReverseStub)
      on_exit(fn -> Application.put_env(:sanbase, Sanbase.Knowledge.Reranker, original || []) end)

      assert Reranker.call("q", candidates) == Enum.reverse(candidates)
    end
  end
end
