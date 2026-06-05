defmodule Sanbase.Knowledge.RecencyIntentTest do
  use ExUnit.Case, async: true

  alias Sanbase.Knowledge.RecencyIntent

  describe "detect?/1 — positive (recency cues)" do
    for query <- [
          "gimme newest btc article",
          "latest bitcoin insight",
          "what is the most recent ETH analysis",
          "recent on-chain reports",
          "show me recently published insights",
          "up to date metrics docs",
          "up-to-date metrics docs",
          "what happened today",
          "anything from this week",
          "insights from this month",
          "best calls this year",
          "btc articles from the past 7 days",
          "last 30 days of insights",
          "posts from the last week",
          "anything in the past few months"
        ] do
      test "flags: #{query}" do
        assert RecencyIntent.detect?(unquote(query))
      end
    end
  end

  describe "detect?/1 — positive (misspellings)" do
    for query <- [
          "gimme the latets btc article",
          "lastest insights please",
          "newst eth report",
          "what is the recancy of this",
          "recnet on-chain data",
          "todya's market recap"
        ] do
      test "flags typo: #{query}" do
        assert RecencyIntent.detect?(unquote(query))
      end
    end
  end

  describe "detect?/1 — negative (no recency cue)" do
    for query <- [
          "what is MVRV",
          "explain bitcoin price history",
          "current ratio definition",
          "what is the new metric about",
          "now what does whale mean",
          "the last halving impact on price",
          "last cycle top",
          "how does social volume work",
          # real words one edit away from a recency word — deliberately NOT typos
          "recant the previous statement",
          "latent demand for the token",
          "newer vs older addresses"
        ] do
      test "does not flag: #{query}" do
        refute RecencyIntent.detect?(unquote(query))
      end
    end
  end

  describe "detect?/1 — non-binary input" do
    test "returns false for nil" do
      refute RecencyIntent.detect?(nil)
    end

    test "returns false for non-string" do
      refute RecencyIntent.detect?(123)
    end
  end

  describe "strip/1" do
    test "removes recency words, keeps the topic" do
      assert RecencyIntent.strip("gimme the latest btc article") == "gimme the btc article"
    end

    test "removes multi-word recency phrases" do
      assert RecencyIntent.strip("show me the most recent eth data") == "show me the eth data"
    end

    test "leaves a non-recency query unchanged" do
      assert RecencyIntent.strip("what is MVRV") == "what is MVRV"
    end

    test "falls back to the original when only recency words remain" do
      assert RecencyIntent.strip("latest") == "latest"
    end
  end
end
