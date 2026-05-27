defmodule Sanbase.Knowledge.Reranker.CandidateFormatter do
  @moduledoc """
  Builds `Sanbase.Knowledge.Reranker.candidate/0` maps from raw retrieval
  entries (FAQ rows, Academy chunks, Insight chunks), formatting the
  `text` field according to what each reranker backend prefers.

  Two formatting styles are recognized:

    * `:llm_listwise` — the candidate is one block inside a prompt sent
      to a chat model (OpenAI, Anthropic, etc.). The model is reasoning
      over many candidates side-by-side, so explicit structural labels
      (`Q:` / `A:` / `Title:`) help it differentiate parts and produce
      consistent rankings.

    * `:cross_encoder` — the candidate is sent to a dedicated rerank
      model (Cohere rerank-3.5, BGE, Voyage). Those models are trained
      on prose passages, not synthetic `Q:/A:` blobs. Documents look
      like real text with the most informative line first.

  Each reranker module may export `style/0` to declare which style it
  wants. Modules that omit it default to `:llm_listwise`.
  """

  alias Sanbase.Knowledge.Reranker

  @type style :: :llm_listwise | :cross_encoder
  @type source :: :faq | :academy | :insight

  @doc """
  Turn raw entries into reranker-ready candidates for the given source.

  `reranker_mod` controls how the `text` field is composed.
  """
  @spec to_candidates([map()], source(), module()) :: [Reranker.candidate()]
  def to_candidates(entries, source, reranker_mod) do
    style = style_for(reranker_mod)
    Enum.map(entries, &to_candidate(&1, source, style))
  end

  @doc """
  Resolve the formatting style a reranker module wants.

  Returns `:llm_listwise` for modules that do not export `style/0`.
  """
  @spec style_for(module()) :: style()
  def style_for(mod) do
    cond do
      is_nil(mod) -> :llm_listwise
      not Code.ensure_loaded?(mod) -> :llm_listwise
      function_exported?(mod, :style, 0) -> mod.style()
      true -> :llm_listwise
    end
  end

  # Candidate construction per source --------------------------------

  defp to_candidate(entry, :faq, style) do
    %{
      id: entry.id,
      text: faq_text(entry, style),
      similarity: entry.similarity,
      source: :faq,
      metadata: entry
    }
  end

  defp to_candidate(entry, :academy, style) do
    title = Map.get(entry, :title, "")
    body = Map.get(entry, :chunk) || Map.get(entry, :content_markdown) || ""

    %{
      id: Map.get(entry, :github_path) || Map.get(entry, :id) || Map.get(entry, :url),
      text: academy_text(title, body, style),
      similarity: entry.similarity,
      source: :academy,
      metadata: entry
    }
  end

  defp to_candidate(entry, :insight, style) do
    title = Map.get(entry, :post_title) || Map.get(entry, :title) || ""

    body =
      Map.get(entry, :text_chunk) || Map.get(entry, :short_desc) || Map.get(entry, :text) || ""

    %{
      id: Map.get(entry, :post_id) || Map.get(entry, :id),
      text: insight_text(title, body, style),
      similarity: entry.similarity,
      source: :insight,
      metadata: entry
    }
  end

  # Per-source, per-style text composition ---------------------------

  # Listwise LLM wants labeled Q/A so it can identify question vs answer
  # in a prompt full of candidates.
  defp faq_text(e, :llm_listwise),
    do: "Q: #{e.question}\n\nA: #{e.answer_markdown}"

  # Cross-encoder wants prose: question acts as a title, answer as body.
  defp faq_text(e, :cross_encoder),
    do: "#{e.question}\n\n#{e.answer_markdown}"

  defp academy_text(title, body, :llm_listwise),
    do: "Title: #{title}\n\n#{body}"

  defp academy_text(title, body, :cross_encoder),
    do: prose_join(title, body)

  defp insight_text(title, body, :llm_listwise),
    do: "Title: #{title}\n\n#{body}"

  defp insight_text(title, body, :cross_encoder),
    do: prose_join(title, body)

  defp prose_join("", body), do: body
  defp prose_join(title, ""), do: title
  defp prose_join(title, body), do: "#{title}\n\n#{body}"
end
