defmodule Sanbase.KnowledgeTest do
  use ExUnit.Case, async: true

  alias Sanbase.Knowledge
  alias Sanbase.Knowledge.QueryPlan
  alias Sanbase.Knowledge.Reranker.Noop

  defmodule ReverseStub do
    @behaviour Sanbase.Knowledge.Reranker
    @impl true
    def rerank(_query, candidates, _opts), do: {:ok, Enum.reverse(candidates)}
  end

  # Drops the candidate whose insight post_id is 2, to prove the rerank stage
  # runs (and filters) BEFORE the date sort on the recency path.
  defmodule DropPostTwoStub do
    @behaviour Sanbase.Knowledge.Reranker
    @impl true
    def rerank(_query, candidates, _opts) do
      {:ok, Enum.reject(candidates, &(&1.metadata.post_id == 2))}
    end
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

  describe "order_insights/5" do
    defp insight(post_id, similarity, published_at) do
      %{
        post_id: post_id,
        post_title: "post #{post_id}",
        text_chunk: "body #{post_id}",
        similarity: similarity,
        published_at: published_at
      }
    end

    # A plan that asks for recency ordering — `order_insights` reads the sort
    # directive from `options[:query_plan]`.
    defp recency_plan(), do: %QueryPlan{semantic_query: "x", sort: :recency}

    test "recency sort orders newest-first by published_at, ignoring similarity" do
      old = insight(1, 0.9, ~N[2019-01-01 00:00:00])
      newest = insight(2, 0.5, ~N[2026-01-01 00:00:00])
      mid = insight(3, 0.7, ~N[2022-06-01 00:00:00])

      result =
        Knowledge.order_insights([old, newest, mid], "gimme newest btc article", :insight,
          query_plan: recency_plan(),
          reranker: Noop
        )

      assert Enum.map(result, & &1.post_id) == [2, 3, 1]
    end

    test "recency sort truncates to :top_n after ordering" do
      old = insight(1, 0.9, ~N[2019-01-01 00:00:00])
      newest = insight(2, 0.5, ~N[2026-01-01 00:00:00])
      mid = insight(3, 0.7, ~N[2022-06-01 00:00:00])

      result =
        Knowledge.order_insights(
          [old, newest, mid],
          "latest insights",
          :insight,
          [query_plan: recency_plan(), reranker: Noop],
          top_n: 2
        )

      assert Enum.map(result, & &1.post_id) == [2, 3]
    end

    test "recency sort places entries without a published_at last" do
      dated = insight(1, 0.9, ~N[2020-01-01 00:00:00])
      undated = insight(2, 0.9, nil)

      result =
        Knowledge.order_insights([undated, dated], "newest posts", :insight,
          query_plan: recency_plan(),
          reranker: Noop
        )

      assert Enum.map(result, & &1.post_id) == [1, 2]
    end

    test "recency sort keeps distinct documents (a multi-chunk post can't crowd out a newer one)" do
      # Regression: post 1 (old) contributes three highly-relevant chunks; post 2
      # (new) one less-relevant chunk. Gating relevance on chunks would keep all
      # three of post 1 first and bury post 2. The document-level window must
      # surface post 2 as the newest distinct document; post 1's sibling chunks
      # stay grouped BEHIND it (kept for downstream backfill, not collapsed).
      old_a = insight(1, 0.9, ~N[2019-01-01 00:00:00])
      old_b = insight(1, 0.85, ~N[2019-01-01 00:00:00])
      old_c = insight(1, 0.8, ~N[2019-01-01 00:00:00])
      newest = insight(2, 0.5, ~N[2026-01-01 00:00:00])

      result =
        Knowledge.order_insights([old_a, old_b, old_c, newest], "newest btc", :insight,
          query_plan: recency_plan(),
          reranker: Noop
        )

      assert Enum.map(result, & &1.post_id) == [2, 1, 1, 1]
      # within post 1 the rerank (here: input) order is preserved
      assert Enum.map(result, & &1.similarity) == [0.5, 0.9, 0.85, 0.8]
    end

    test "recency chunks feed diversify_by_document: one chunk per newest doc, then backfill" do
      # End-to-end shape of the answer path: order_insights groups all chunks
      # behind their documents newest-first; diversify_by_document then
      # round-robins so the prompt leads with one chunk per distinct (newest)
      # document and BACKFILLS from sibling chunks when documents run out.
      old_a = %{insight(1, 0.9, ~N[2019-01-01 00:00:00]) | text_chunk: "old chunk a"}
      old_b = %{insight(1, 0.85, ~N[2019-01-01 00:00:00]) | text_chunk: "old chunk b"}
      new_a = %{insight(2, 0.6, ~N[2026-01-01 00:00:00]) | text_chunk: "new chunk a"}
      new_b = %{insight(2, 0.55, ~N[2026-01-01 00:00:00]) | text_chunk: "new chunk b"}

      result =
        [old_a, old_b, new_a, new_b]
        |> Knowledge.order_insights("newest btc", :insight,
          query_plan: recency_plan(),
          reranker: Noop
        )
        |> Knowledge.diversify_by_document(& &1.post_id, 3)

      assert Enum.map(result, & &1.text_chunk) == ["new chunk a", "old chunk a", "new chunk b"]
    end

    test "recency sort reranks for relevance before date-sorting" do
      # The stub reranker drops post 2 (the newest). If the date sort ran on the
      # raw cosine pool it would top the result; getting [3, 1] proves the rerank
      # gate runs first and only its survivors are date-sorted.
      old = insight(1, 0.9, ~N[2019-01-01 00:00:00])
      newest = insight(2, 0.5, ~N[2026-01-01 00:00:00])
      mid = insight(3, 0.7, ~N[2022-06-01 00:00:00])

      result =
        Knowledge.order_insights([old, newest, mid], "newest btc", :insight,
          query_plan: recency_plan(),
          reranker: DropPostTwoStub
        )

      assert Enum.map(result, & &1.post_id) == [3, 1]
    end

    test "relevance sort (no recency plan) reranks rather than date-sorting" do
      # No query_plan -> relevance. Input [newest, old]; ReverseStub reverses to
      # [old, newest] = [1, 2]. A date sort would give [2, 1], so [1, 2] proves
      # the rerank path ran and date ordering did NOT.
      newest = insight(2, 0.5, ~N[2026-01-01 00:00:00])
      old = insight(1, 0.9, ~N[2019-01-01 00:00:00])

      result =
        Knowledge.order_insights([newest, old], "what is MVRV", :insight, reranker: ReverseStub)

      assert Enum.map(result, & &1.post_id) == [1, 2]
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
