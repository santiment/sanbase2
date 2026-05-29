defmodule Sanbase.Knowledge.EvalTest do
  use ExUnit.Case, async: true

  alias Sanbase.Knowledge.Eval

  describe "score_hits/3" do
    test "marks skipped when no expected ids" do
      hits = [%{id: "a", similarity: 0.9}]

      result = Eval.score_hits(hits, [], & &1.id)

      assert result.skipped == true
      assert result.top1_similarity == 0.9
      assert result.retrieved == 1
      assert result.expected_count == 0
    end

    test "hit at rank 1 when first hit matches" do
      hits = [
        %{id: "wanted", similarity: 0.9},
        %{id: "other", similarity: 0.5}
      ]

      result = Eval.score_hits(hits, ["wanted"], & &1.id)

      assert result.first_rank == 1
      assert result.mrr == 1.0
      assert result.hit_at_1 == true
      assert result.hit_at_3 == true
      assert result.hit_at_5 == true
      assert result.hit_at_10 == true
    end

    test "hit at rank 3 gives mrr=1/3 and misses hit@1" do
      hits = [
        %{id: "a", similarity: 0.9},
        %{id: "b", similarity: 0.8},
        %{id: "wanted", similarity: 0.7}
      ]

      result = Eval.score_hits(hits, ["wanted"], & &1.id)

      assert result.first_rank == 3
      assert_in_delta result.mrr, 1 / 3, 1.0e-9
      assert result.hit_at_1 == false
      assert result.hit_at_3 == true
      assert result.hit_at_5 == true
    end

    test "no hit gives zero MRR and false hit@K" do
      hits = [
        %{id: "a", similarity: 0.9},
        %{id: "b", similarity: 0.8}
      ]

      result = Eval.score_hits(hits, ["nope"], & &1.id)

      assert result.first_rank == 0
      assert result.mrr == 0.0
      assert result.hit_at_1 == false
      assert result.hit_at_10 == false
      assert result.top1_similarity == 0.9
    end

    test "empty hits give nil top1 and zero mrr" do
      result = Eval.score_hits([], ["x"], & &1.id)

      assert result.first_rank == 0
      assert result.mrr == 0.0
      assert result.top1_similarity == nil
      assert result.retrieved == 0
    end

    test "uses provided id_fn for matching" do
      hits = [%{post_id: 42, similarity: 0.7}]

      result = Eval.score_hits(hits, [42], & &1.post_id)

      assert result.hit_at_1 == true
      assert result.mrr == 1.0
    end
  end

  describe "context_recall/2" do
    test "returns nil when there are no facts" do
      assert Eval.context_recall("anything", []) == nil
    end

    test "full recall when every fact is present" do
      ctx = "MVRV above 3 historically signals overvaluation."
      facts = ["MVRV above 3", "overvaluation"]

      assert %{recall: 1.0, matched: 2, total: 2} = Eval.context_recall(ctx, facts)
    end

    test "partial recall counts only present facts" do
      ctx = "Realized value is the price at which each coin last moved."
      facts = ["realized value", "thermocap ratio"]

      assert %{recall: recall, matched: 1, total: 2} = Eval.context_recall(ctx, facts)
      assert_in_delta recall, 0.5, 1.0e-9
    end

    test "matching ignores case and punctuation" do
      ctx = "The API speaks GraphQL, not REST."
      facts = ["graphql"]

      assert %{recall: 1.0, matched: 1} = Eval.context_recall(ctx, facts)
    end

    test "zero recall when no fact matches" do
      assert %{recall: +0.0, matched: 0, total: 1} =
               Eval.context_recall("unrelated text", ["missing phrase"])
    end
  end

  describe "summarize/2 context section" do
    test "averages recall and chars over items with facts" do
      results = [
        %{id: "a", context: %{recall: 1.0, matched: 2, total: 2, text_chars: 100}},
        %{id: "b", context: %{recall: 0.5, matched: 1, total: 2, text_chars: 200}},
        # no facts → skipped
        %{id: "c", context: %{recall: nil, text_chars: 50}}
      ]

      %{context: context} = Eval.summarize(results, [:faq])

      assert context.evaluated == 2
      assert_in_delta context.mean_recall, 0.75, 1.0e-9
      assert_in_delta context.mean_chars, 150.0, 1.0e-9
    end

    test "evaluated=0 when no item carries facts" do
      results = [%{id: "a", context: %{recall: nil, text_chars: 10}}]

      assert %{context: %{evaluated: 0}} = Eval.summarize(results, [:faq])
    end
  end

  describe "summarize/2" do
    test "skips items with no expected ids" do
      results = [
        %{id: "a", faq: %{skipped: true, top1_similarity: 0.6}},
        %{
          id: "b",
          faq: %{
            mrr: 1.0,
            hit_at_1: true,
            hit_at_3: true,
            hit_at_5: true,
            hit_at_10: true,
            top1_similarity: 0.9,
            first_rank: 1,
            retrieved: 5,
            expected_count: 1
          }
        }
      ]

      %{faq: faq} = Eval.summarize(results, [:faq])

      assert faq.evaluated == 1
      assert faq.hit_at_1 == 1.0
      assert faq.mean_mrr == 1.0
    end

    test "averages hit-rate as fraction of evaluated items" do
      results = [
        item_with(:faq, %{
          first_rank: 1,
          mrr: 1.0,
          hit_at_1: true,
          hit_at_3: true,
          hit_at_5: true,
          hit_at_10: true,
          top1_similarity: 0.9
        }),
        item_with(:faq, %{
          first_rank: 0,
          mrr: 0.0,
          hit_at_1: false,
          hit_at_3: false,
          hit_at_5: false,
          hit_at_10: false,
          top1_similarity: 0.4
        })
      ]

      %{faq: faq} = Eval.summarize(results, [:faq])

      assert faq.evaluated == 2
      assert faq.hit_at_1 == 0.5
      assert faq.mean_mrr == 0.5
      assert_in_delta faq.mean_top1_similarity, 0.65, 1.0e-9
    end

    test "returns evaluated=0 when every item is skipped or missing" do
      results = [
        %{id: "a", faq: %{skipped: true, top1_similarity: 0.5}},
        %{id: "b", faq: nil}
      ]

      %{faq: faq} = Eval.summarize(results, [:faq])

      assert faq == %{evaluated: 0}
    end
  end

  defp item_with(source, score) do
    Map.put(%{id: "x"}, source, Map.merge(%{retrieved: 5, expected_count: 1}, score))
  end
end
