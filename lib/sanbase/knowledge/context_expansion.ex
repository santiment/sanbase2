defmodule Sanbase.Knowledge.ContextExpansion do
  @moduledoc """
  Optional retrieval step that widens each matched chunk with its immediate
  neighbours (previous and next by `chunk_index`) from the same parent
  document, then stitches them with `Sanbase.Knowledge.Unchunker` so the answer
  prompt sees a continuous passage instead of a single isolated chunk.

  Only insight and academy hits are chunked; FAQ entries are whole and never
  reach here. Hits without an integer `chunk_index` (legacy insight rows
  indexed before the column existed) are left untouched, so enabling the
  feature can never drop a hit — at worst it leaves it as-is.

  This is the enrichment seam described in `Sanbase.Knowledge.Context`: it
  replaces the hit's text field (`:text_chunk` for insights, `:chunk` for
  academy) in place, so `Context.assemble/2` renders the widened passage
  transparently.
  """

  alias Sanbase.Insight.PostEmbedding
  alias Sanbase.Knowledge.AcademyArticleChunk
  alias Sanbase.Knowledge.Unchunker

  # Neighbours to pull on each side of the matched chunk (1 = prev + next).
  @radius 1

  @doc """
  Expand each hit with its neighbouring chunks, returning the hits with their
  text field replaced by the stitched passage. Unknown sources and hits that
  cannot be located by `(parent, chunk_index)` pass through unchanged.
  """
  @spec expand([map()], :insight | :academy, keyword()) :: [map()]
  def expand(hits, source, opts \\ [])

  def expand([], _source, _opts), do: []

  def expand(hits, :insight, opts) do
    radius = Keyword.get(opts, :radius, @radius)
    Enum.map(hits, &expand_insight(&1, radius))
  end

  def expand(hits, :academy, opts) do
    radius = Keyword.get(opts, :radius, @radius)
    Enum.map(hits, &expand_academy(&1, radius))
  end

  def expand(hits, _source, _opts), do: hits

  defp expand_insight(%{post_id: post_id, chunk_index: idx} = hit, radius)
       when is_integer(post_id) and is_integer(idx) do
    merged =
      post_id
      |> PostEmbedding.fetch_chunks(neighbour_indices(idx, radius))
      |> Enum.map(&insight_body(&1.text_chunk))
      |> Unchunker.merge()

    if merged == "", do: hit, else: %{hit | text_chunk: merged}
  end

  defp expand_insight(hit, _radius), do: hit

  defp expand_academy(%{article_id: article_id, chunk_index: idx} = hit, radius)
       when is_integer(article_id) and is_integer(idx) do
    merged =
      article_id
      |> AcademyArticleChunk.fetch_chunks(neighbour_indices(idx, radius))
      |> Enum.map(& &1.content)
      |> Unchunker.merge()

    if merged == "", do: hit, else: %{hit | chunk: merged}
  end

  defp expand_academy(hit, _radius), do: hit

  # chunk_index is 0-based and contiguous per parent, so the neighbour window is
  # [idx - radius, idx + radius] clamped at 0. Missing upper indices simply are
  # not returned by the fetch.
  defp neighbour_indices(idx, radius) do
    Enum.to_list(max(0, idx - radius)..(idx + radius))
  end

  # Insight chunk text is stored wrapped with a title preamble; keep only what
  # follows the writer's marker so neighbours stitch without repeating the title.
  defp insight_body(text) do
    marker = PostEmbedding.chunk_text_marker()

    case String.split(text || "", marker, parts: 2) do
      [_, body] -> String.trim(body)
      _ -> String.trim(text || "")
    end
  end
end
