defmodule Sanbase.Knowledge.UnchunkerTest do
  use ExUnit.Case, async: true

  alias Sanbase.Knowledge.Unchunker

  # Mirrors how TextChunker would split this source with overlap: chunk B
  # starts before chunk A ends, so naive concat would duplicate the overlap.
  @source "The quick brown fox jumps over the lazy dog near the river bank."

  defp chunk(start_byte, end_byte) do
    %{start_byte: start_byte, end_byte: end_byte}
  end

  describe "unchunk/3" do
    test "single chunk returns exactly its source slice" do
      c = chunk(4, 19)
      assert Unchunker.unchunk(@source, [c]) == binary_part(@source, 4, 15)
    end

    test "overlapping chunks reconstruct the original span without duplication" do
      # A = [0, 25), B = [19, 44) overlap on bytes [19, 25)
      a = chunk(0, 25)
      b = chunk(19, 44)

      assert Unchunker.unchunk(@source, [a, b]) == binary_part(@source, 0, 44)
    end

    test "order does not matter — sorted by start_byte" do
      a = chunk(0, 25)
      b = chunk(19, 44)

      assert Unchunker.unchunk(@source, [b, a]) == binary_part(@source, 0, 44)
    end

    test "adjacent (touching) chunks merge into one span" do
      a = chunk(0, 20)
      b = chunk(20, 40)

      assert Unchunker.unchunk(@source, [a, b]) == binary_part(@source, 0, 40)
    end

    test "non-contiguous chunks become separate spans joined by separator" do
      a = chunk(0, 10)
      b = chunk(30, 40)

      result = Unchunker.unchunk(@source, [a, b], separator: "##")

      assert result == binary_part(@source, 0, 10) <> "##" <> binary_part(@source, 30, 10)
    end

    test "a fully contained chunk does not extend the span" do
      outer = chunk(0, 40)
      inner = chunk(10, 20)

      assert Unchunker.unchunk(@source, [inner, outer]) == binary_part(@source, 0, 40)
    end

    # Byte layout of "héllo world": 0:h, 1-2:é (0xC3 0xA9), 3:l, 4:l, 5:o,
    # 6:space, 7:w, 8:o, 9:r, 10:l, 11:d. byte_size == 12.
    test "trims a trailing mid-codepoint cut, keeps the valid prefix" do
      source = "héllo world"
      assert byte_size(source) == 12

      # [0,2) = "h" + lead byte of é → trailing partial codepoint trimmed → "h"
      assert Unchunker.unchunk(source, [chunk(0, 2)]) == "h"

      # codepoint-aligned slice over the same char is untouched
      assert Unchunker.unchunk(source, [chunk(0, 3)]) == "hé"
    end

    test "trims a leading mid-codepoint cut, keeps the valid remainder" do
      source = "héllo world"

      # [2,6) starts inside é (continuation byte 0xA9) → leading byte dropped → "llo"
      assert Unchunker.unchunk(source, [chunk(2, 6)]) == "llo"
    end

    test "drops a span only if it trims to empty" do
      # a slice that is entirely a continuation byte salvages nothing
      source = "é"
      assert Unchunker.unchunk(source, [chunk(1, 2)]) == nil
    end

    test "trims the broken span and keeps the valid one" do
      source = "héllo world"
      good = chunk(4, 11)
      broken = chunk(0, 2)

      assert Unchunker.unchunk(source, [broken, good], separator: "|") ==
               "h" <> "|" <> binary_part(source, 4, 7)
    end

    test "cut at BOTH ends keeps the valid interior" do
      # "€A€": bytes 0-2 first € (E2 82 AC), 3 'A', 4-6 second € (E2 82 AC).
      source = "€A€"
      assert byte_size(source) == 7

      # [2,5): starts on a continuation byte of the first € and ends inside
      # the second € → both edges trimmed, interior "A" survives.
      assert Unchunker.unchunk(source, [chunk(2, 5)]) == "A"
    end

    test "trailing cut of a 3-byte codepoint trims the 2 dangling bytes" do
      # "ab€": 'a','b', then € = E2 82 AC.
      source = "ab€"
      assert byte_size(source) == 5

      # [0,4) keeps "ab" + 2 of €'s 3 bytes → incomplete tail trimmed → "ab"
      assert Unchunker.unchunk(source, [chunk(0, 4)]) == "ab"
    end

    test "leading cut drops multiple continuation bytes of a 4-byte codepoint" do
      # "😀x": emoji = F0 9F 98 80 (4 bytes), then 'x'.
      source = "😀x"
      assert byte_size(source) == 5

      # [2,5) starts 2 bytes into the emoji → both continuation bytes dropped → "x"
      assert Unchunker.unchunk(source, [chunk(2, 5)]) == "x"
    end

    test "returns nil when no chunk has usable offsets" do
      assert Unchunker.unchunk(@source, [%{start_byte: nil, end_byte: nil}]) == nil
      assert Unchunker.unchunk(@source, []) == nil
    end

    test "ignores chunks with out-of-range or inverted offsets" do
      good = chunk(0, 10)
      out_of_range = chunk(0, byte_size(@source) + 50)
      inverted = chunk(20, 10)

      assert Unchunker.unchunk(@source, [good, out_of_range, inverted]) ==
               binary_part(@source, 0, 10)
    end
  end

  describe "spans/2" do
    test "returns one string per contiguous group" do
      spans = Unchunker.spans(@source, [chunk(0, 10), chunk(8, 18), chunk(40, 50)])

      assert [first, second] = spans
      assert first == binary_part(@source, 0, 18)
      assert second == binary_part(@source, 40, 10)
    end
  end
end
