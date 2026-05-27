defmodule Sanbase.Knowledge.Reranker.CandidateFormatterTest do
  use ExUnit.Case, async: true

  alias Sanbase.Knowledge.Reranker.CandidateFormatter

  defmodule ListwiseReranker do
    def style(), do: :llm_listwise
  end

  defmodule CrossEncoderReranker do
    def style(), do: :cross_encoder
  end

  defmodule UnstyledReranker do
  end

  describe "style_for/1" do
    test "defaults to :llm_listwise when module is nil" do
      assert CandidateFormatter.style_for(nil) == :llm_listwise
    end

    test "defaults to :llm_listwise when module doesn't export style/0" do
      assert CandidateFormatter.style_for(UnstyledReranker) == :llm_listwise
    end

    test "returns the declared style for listwise modules" do
      assert CandidateFormatter.style_for(ListwiseReranker) == :llm_listwise
    end

    test "returns the declared style for cross-encoder modules" do
      assert CandidateFormatter.style_for(CrossEncoderReranker) == :cross_encoder
    end
  end

  describe "FAQ formatting" do
    defp faq_entry(),
      do: %{
        id: 42,
        question: "Where do I get my Santiment API key?",
        answer_markdown: "Visit your account settings page.",
        similarity: 0.91
      }

    test "listwise gets labeled Q:/A: blocks" do
      [c] = CandidateFormatter.to_candidates([faq_entry()], :faq, ListwiseReranker)

      assert c.id == 42
      assert c.source == :faq
      assert c.similarity == 0.91

      assert c.text ==
               "Q: Where do I get my Santiment API key?\n\nA: Visit your account settings page."

      assert c.metadata == faq_entry()
    end

    test "cross-encoder gets prose-style (no Q:/A: labels)" do
      [c] = CandidateFormatter.to_candidates([faq_entry()], :faq, CrossEncoderReranker)

      assert c.text == "Where do I get my Santiment API key?\n\nVisit your account settings page."
      refute c.text =~ "Q:"
      refute c.text =~ "A:"
    end
  end

  describe "Academy formatting" do
    defp academy_entry(),
      do: %{
        github_path: "metrics/mvrv.md",
        title: "MVRV Ratio",
        chunk: "MVRV measures the ratio between market cap and realized cap.",
        similarity: 0.84
      }

    test "listwise gets a Title: label" do
      [c] = CandidateFormatter.to_candidates([academy_entry()], :academy, ListwiseReranker)

      assert c.id == "metrics/mvrv.md"
      assert c.text =~ "Title: MVRV Ratio"
      assert c.text =~ "MVRV measures the ratio"
    end

    test "cross-encoder gets prose with title as the lead line" do
      [c] = CandidateFormatter.to_candidates([academy_entry()], :academy, CrossEncoderReranker)

      assert c.text ==
               "MVRV Ratio\n\nMVRV measures the ratio between market cap and realized cap."

      refute c.text =~ "Title:"
    end

    test "falls back to content_markdown when chunk is absent" do
      entry = %{
        github_path: "x.md",
        title: "X",
        content_markdown: "body via content_markdown",
        similarity: 0.5
      }

      [c] = CandidateFormatter.to_candidates([entry], :academy, CrossEncoderReranker)
      assert c.text =~ "body via content_markdown"
    end
  end

  describe "Insight formatting" do
    defp insight_entry(),
      do: %{
        post_id: 7,
        post_title: "Bitcoin Network Activity Rising",
        text_chunk: "Active addresses up 15% week-over-week.",
        similarity: 0.77
      }

    test "listwise gets a Title: label" do
      [c] = CandidateFormatter.to_candidates([insight_entry()], :insight, ListwiseReranker)
      assert c.id == 7
      assert c.text =~ "Title: Bitcoin Network Activity Rising"
    end

    test "cross-encoder gets prose with no label" do
      [c] = CandidateFormatter.to_candidates([insight_entry()], :insight, CrossEncoderReranker)

      assert c.text ==
               "Bitcoin Network Activity Rising\n\nActive addresses up 15% week-over-week."

      refute c.text =~ "Title:"
    end

    test "uses post_id when present, falls back to id" do
      entry = insight_entry() |> Map.put(:post_id, nil) |> Map.put(:id, 999)
      [c1] = CandidateFormatter.to_candidates([entry], :insight, ListwiseReranker)
      assert c1.id == 999
    end
  end

  describe "graceful fallbacks for unstyled rerankers" do
    test "unstyled reranker is treated as listwise" do
      [c] =
        CandidateFormatter.to_candidates(
          [%{id: 1, question: "q", answer_markdown: "a", similarity: 0.5}],
          :faq,
          UnstyledReranker
        )

      assert c.text =~ "Q: q"
    end
  end
end
