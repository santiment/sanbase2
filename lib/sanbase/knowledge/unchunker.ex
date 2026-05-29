defmodule Sanbase.Knowledge.Unchunker do
  @moduledoc """
  Reconstructs original document spans from a set of picked chunks.

  Chunks produced by `TextChunker` overlap (e.g. chunk_size 2000, overlap
  200), so concatenating their stored text duplicates the overlap regions.
  Instead, each chunk carries the byte offsets (`start_byte`/`end_byte`) of
  where it sits in the source markdown. To "unchunk" we simply slice the
  source between the first picked chunk's start and the last picked chunk's
  end — the original text, with overlaps and trimming undone for free.

  Picked chunks that are not contiguous (a gap between one chunk's end and
  the next chunk's start) are reconstructed as separate spans so unrelated
  regions of the document are not silently glued together.

  All offsets are byte offsets and slicing uses `binary_part/3`, matching
  how `TextChunker` measures. Chunk boundaries are valid UTF-8 codepoint
  boundaries, so the slices are always valid strings.
  """

  @type chunk :: %{
          optional(any()) => any(),
          required(:start_byte) => non_neg_integer() | nil,
          required(:end_byte) => non_neg_integer() | nil
        }

  @doc """
  Reconstruct the source span(s) covered by `chunks` from `source`.

  Returns a list of strings in document order — one per contiguous group of
  picked chunks. Chunks missing offsets are ignored. Returns `[]` when no
  chunk has usable offsets (the caller should then fall back to stored
  chunk text).

  If a span's offsets cut a multibyte codepoint (stale offsets, e.g. an
  insight edited after embedding), only the misaligned bytes at the span's
  edges are trimmed — the valid interior is kept. A byte slice of valid
  UTF-8 can only be broken at its two endpoints, never in the middle, so
  this preserves all but a few boundary bytes. A span that trims to empty
  is dropped. Slicing the exact source the offsets came from is always
  codepoint-aligned, so trimming is a no-op on the common path.
  """
  @spec spans(String.t(), [chunk()]) :: [String.t()]
  def spans(source, chunks) when is_binary(source) and is_list(chunks) do
    chunks
    |> Enum.filter(&valid_offsets?(&1, source))
    |> Enum.sort_by(& &1.start_byte)
    |> group_contiguous()
    |> Enum.map(fn group -> source |> slice_group(group) |> repair_utf8() end)
    |> Enum.reject(&(&1 == ""))
  end

  @doc """
  Reconstruct and join all spans into a single string.

  Separate (non-contiguous) spans are joined with `separator`, which
  defaults to a marker making the gap visible to the reader/LLM. Returns
  `nil` when nothing can be reconstructed, so callers can fall back.
  """
  @spec unchunk(String.t(), [chunk()], keyword()) :: String.t() | nil
  def unchunk(source, chunks, opts \\ [])

  def unchunk(source, chunks, opts) when is_binary(source) and is_list(chunks) do
    separator = Keyword.get(opts, :separator, "\n\n[…]\n\n")

    case spans(source, chunks) do
      [] -> nil
      spans -> Enum.join(spans, separator)
    end
  end

  def unchunk(_source, _chunks, _opts), do: nil

  # A chunk's offsets are usable only when both are present, ordered, and
  # within the source. Guards against stale offsets after a source edit.
  defp valid_offsets?(%{start_byte: s, end_byte: e}, source)
       when is_integer(s) and is_integer(e) and s >= 0 and e > s do
    e <= byte_size(source)
  end

  defp valid_offsets?(_chunk, _source), do: false

  # Group sorted chunks into contiguous `{start_byte, end_byte}` bounds. A
  # new group starts when a chunk begins past the end already covered by the
  # current group.
  defp group_contiguous([]), do: []

  defp group_contiguous([first | rest]) do
    {closed, {gs, ge}} =
      Enum.reduce(rest, {[], {first.start_byte, first.end_byte}}, fn c, {closed, {gs, ge}} ->
        if c.start_byte <= ge do
          {closed, {gs, max(ge, c.end_byte)}}
        else
          {[{gs, ge} | closed], {c.start_byte, c.end_byte}}
        end
      end)

    Enum.reverse([{gs, ge} | closed])
  end

  defp slice_group(source, {start_byte, end_byte}) do
    binary_part(source, start_byte, end_byte - start_byte)
  end

  # Trim only the misaligned bytes at the edges of a slice, keeping the valid
  # interior. Fast-path: a correctly-aligned slice is already valid and is
  # returned untouched.
  defp repair_utf8(binary) do
    if String.valid?(binary) do
      binary
    else
      binary |> drop_leading_continuation() |> take_valid_prefix()
    end
  end

  # A slice that starts mid-codepoint begins with UTF-8 continuation bytes
  # (0b10xxxxxx, i.e. 0x80..0xBF); drop them until a codepoint start.
  defp drop_leading_continuation(<<byte, rest::binary>>) when byte in 0x80..0xBF,
    do: drop_leading_continuation(rest)

  defp drop_leading_continuation(binary), do: binary

  # Keep the longest valid UTF-8 prefix, discarding an incomplete trailing
  # codepoint left by a slice that ends mid-codepoint.
  defp take_valid_prefix(binary) do
    case :unicode.characters_to_binary(binary) do
      valid when is_binary(valid) -> valid
      {:incomplete, valid, _rest} -> valid
      {:error, valid, _rest} -> valid
    end
  end
end
