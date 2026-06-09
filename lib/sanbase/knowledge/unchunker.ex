defmodule Sanbase.Knowledge.Unchunker do
  @moduledoc """
  Reassembles overlapping chunks into continuous text using only the chunk
  texts themselves — no original document required.

  `TextChunker` emits chunks that overlap (chunk_size 2000, overlap 200): the
  tail of one chunk repeats at the head of the next. `merge/2` stitches an
  ordered list of chunk texts by finding, for each adjacent pair, the longest
  run of words that is both a suffix of the left chunk and a prefix of the
  right chunk, then dropping that duplicated run from the right chunk. When no
  overlap is found — non-adjacent chunks, or a clean chunk-size boundary — the
  chunks are joined with a separator so unrelated regions are not silently
  glued together.

  Overlap is matched at WORD granularity, not character: it is cheaper (a few
  dozen token comparisons instead of re-slicing graphemes for every candidate
  length) and more robust, since `String.trim` leaves slightly different
  whitespace at the two seams while chunk boundaries themselves fall on
  whitespace. The duplicated run is then removed from the *original* right
  chunk by slicing at the word boundary, so the remainder keeps its exact
  markdown formatting (newlines, lists, code blocks).

  Working on the chunks alone, rather than slicing the source document by byte
  offset, means reconstruction can never diverge from what was indexed: there
  is no parent entity to re-fetch or re-derive, so a post edited or an article
  reformatted after indexing cannot yield mismatched text. The tradeoff is
  that the result is the stored (already trimmed) chunk text, not a byte-exact
  copy of the original.

  Callers pass chunk texts in document order (e.g. sorted by `chunk_index`)
  and, for insights, with the repeated title template already stripped.
  """

  @default_separator "\n\n[…]\n\n"

  # The real overlap can't exceed the chunker's overlap setting (~200 chars,
  # a few dozen words); cap the search window past it to absorb slack. Require
  # a minimum run so a single coincidental shared word ("the") is not mistaken
  # for the overlap region.
  @max_overlap_words 80
  @min_overlap_words 2

  @doc """
  Merge an ordered list of chunk texts into one string, de-duplicating the
  overlap between adjacent chunks.

  Blank entries are dropped. Returns `""` for an empty list.
  """
  @spec merge([String.t()], keyword()) :: String.t()
  def merge(texts, opts \\ []) when is_list(texts) do
    separator = Keyword.get(opts, :separator, @default_separator)

    texts
    |> Enum.map(&to_string/1)
    |> Enum.reject(&(String.trim(&1) == ""))
    |> case do
      [] -> ""
      [first | rest] -> Enum.reduce(rest, first, &stitch(&2, &1, separator))
    end
  end

  defp stitch(acc, next, separator) do
    case overlap_words(acc, next) do
      0 -> acc <> separator <> next
      k -> acc <> drop_leading_words(next, k)
    end
  end

  # Largest k in [@min_overlap_words, window] such that the last k words of `a`
  # equal the first k words of `b`. Tokenize once, compare within the bounded
  # word windows so the work is proportional to the overlap, not the chunk.
  defp overlap_words(a, b) do
    a_tail = a |> String.split() |> Enum.take(-@max_overlap_words)
    b_head = b |> String.split() |> Enum.take(@max_overlap_words)
    scan_words(a_tail, b_head, min(length(a_tail), length(b_head)))
  end

  defp scan_words(a_tail, b_head, k) when k >= @min_overlap_words do
    if Enum.take(a_tail, -k) == Enum.take(b_head, k),
      do: k,
      else: scan_words(a_tail, b_head, k - 1)
  end

  defp scan_words(_a_tail, _b_head, _k), do: 0

  # Drop the first `k` whitespace-delimited words from `b`, slicing the
  # original string right after the k-th word so the remainder keeps its exact
  # formatting (the cut lands before the following whitespace). The boundary is
  # after a word, an ASCII whitespace position, so it is UTF-8 safe.
  defp drop_leading_words(b, k) do
    case Enum.at(Regex.scan(~r/\S+/u, b, return: :index), k - 1) do
      [{start, len}] -> binary_part(b, start + len, byte_size(b) - start - len)
      _ -> ""
    end
  end
end
