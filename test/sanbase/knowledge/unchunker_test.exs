defmodule Sanbase.Knowledge.UnchunkerTest do
  use ExUnit.Case, async: true

  alias Sanbase.Knowledge.Unchunker

  describe "merge/2" do
    test "empty list returns empty string" do
      assert Unchunker.merge([]) == ""
    end

    test "single chunk is returned unchanged" do
      assert Unchunker.merge(["just one chunk"]) == "just one chunk"
    end

    test "overlapping chunks are stitched without duplicating the overlap" do
      # tail "brown fox" of the first == head "brown fox" of the second
      a = "The quick brown fox"
      b = "brown fox jumps over the lazy dog"

      assert Unchunker.merge([a, b]) == "The quick brown fox jumps over the lazy dog"
    end

    test "three chunks chain through their overlaps" do
      a = "Network value to transactions ratio measures"
      b = "ratio measures how the market cap relates"
      c = "market cap relates to transaction volume"

      assert Unchunker.merge([a, b, c]) ==
               "Network value to transactions ratio measures how the market cap relates to transaction volume"
    end

    test "a chunk fully contained in the previous one adds nothing" do
      a = "alpha beta gamma delta epsilon"
      b = "gamma delta epsilon"

      assert Unchunker.merge([a, b]) == "alpha beta gamma delta epsilon"
    end

    test "non-overlapping chunks are joined with the separator" do
      a = "completely unrelated first paragraph here"
      b = "an entirely different second paragraph"

      assert Unchunker.merge([a, b], separator: "##") ==
               a <> "##" <> b
    end

    test "coincidental short overlap (< min) is not merged" do
      # only "the" would match — below @min_overlap, so they are kept separate
      a = "buy low sell the"
      b = "the moon is far"

      assert Unchunker.merge([a, b], separator: "|") == "buy low sell the|the moon is far"
    end

    test "blank and whitespace-only entries are dropped" do
      a = "real content one two three"
      b = "two three four five six"

      assert Unchunker.merge(["", a, "   \n  ", b, ""]) ==
               "real content one two three four five six"
    end

    test "markdown formatting in the remainder is preserved" do
      a = "intro paragraph about metrics here"
      b = "metrics here\n\n## Heading\n\n- item one\n- item two"

      assert Unchunker.merge([a, b]) ==
               "intro paragraph about metrics here\n\n## Heading\n\n- item one\n- item two"
    end

    test "overlap matching handles multibyte characters" do
      # overlap "at the café" spans a multibyte char; must merge cleanly
      a = "we sat at the café"
      b = "at the café we ordered coffee"

      assert Unchunker.merge([a, b]) == "we sat at the café we ordered coffee"
    end
  end
end
