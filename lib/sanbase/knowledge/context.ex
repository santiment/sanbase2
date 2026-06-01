defmodule Sanbase.Knowledge.Context do
  @moduledoc """
  Builds the per-source context text that goes into the answer prompt.

  Shared by the live prompt builder (`Sanbase.Knowledge`) and the offline
  eval harness (`Sanbase.Knowledge.Eval`) so both exercise the *same*
  assembly logic. Keeping a single source of truth here is what lets the
  eval measure "does the assembled context contain the facts needed to
  answer" without drifting from production.

  Each source produces one entry per hit, every entry leading with a
  `Source marker:` line carrying the markdown link the model must cite
  verbatim. `assemble/2` returns the inner text only — the caller wraps it
  in the source's XML tag.

  This module is also the seam where future context expansion (pulling
  neighbor chunks / parent article around a matched chunk) will plug in:
  the hits passed in already carry their text, so an expansion step that
  enriches `:chunk` / `:text_chunk` before assembly is transparent here and
  measurable by the eval's `context_recall`.
  """

  @doc """
  Assemble the inner context text for a list of reranked hits of one source.

  Returns `""` for an empty hit list. The output is byte-identical to what
  the live prompt embeds between the source's XML tags.
  """
  @spec assemble([map()], :faq | :insight | :academy) :: String.t()
  def assemble([], _source), do: ""

  def assemble(hits, :faq) do
    admin_url = SanbaseWeb.Endpoint.admin_url()

    hits
    |> Enum.map(fn entry ->
      url = "#{admin_url}/admin/faq/#{entry.id}"

      """
      Source marker: [FAQ] [#{faq_label(entry.question)}](#{url})
      Question: #{entry.question}
      Answer: #{entry.answer_markdown}
      """
    end)
    |> Enum.join("\n")
  end

  def assemble(hits, :insight) do
    hits
    |> Enum.map(fn chunk ->
      url = SanbaseWeb.Endpoint.insight_url(chunk.post_id)

      """
      Source marker: [Insight] [#{chunk.post_title}](#{url})
      #{chunk.text_chunk}
      """
    end)
    |> Enum.join("\n\n")
  end

  def assemble(hits, :academy) do
    hits
    |> Enum.map(fn chunk ->
      """
      Source marker: [Academy] [#{chunk.title}](#{chunk.url})
      Most relevant chunk from article: #{chunk.chunk}
      """
    end)
    |> Enum.join("\n")
  end

  # The model cites the marker label verbatim, so a FAQ links via its question
  # (its title) rather than the opaque id. Truncated to keep citations short.
  @faq_label_max 100
  defp faq_label(question) do
    question = String.trim(question || "")

    if String.length(question) > @faq_label_max do
      String.slice(question, 0, @faq_label_max) <> "…"
    else
      question
    end
  end
end
