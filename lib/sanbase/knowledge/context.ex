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
  verbatim. The marker folds the source tag INTO the link text with a
  colon — `[FAQ: label](url)` — so the whole citation is a single markdown
  link that renders as one clickable element. Keeping it a single
  `[...](...)` token (rather than a bare `[FAQ]` tag next to a separate
  `[label](url)` link) is what stops the model from dropping the `(url)`
  and emitting a dead `[FAQ] [label]` with no link. The tag is joined with
  a colon rather than nested brackets (`[[FAQ] label]`) because some
  markdown renderers do not handle brackets inside link text. `assemble/2`
  returns the inner text only — the caller wraps it in the source's XML tag.

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
      Source marker: [FAQ: #{escape_marker_label(faq_label(entry.question))}](#{url})
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
      Source marker: [Insight: #{escape_marker_label(chunk.post_title)}](#{url})
      Published: #{published_on(chunk)}
      #{chunk.text_chunk}
      """
    end)
    |> Enum.join("\n\n")
  end

  def assemble(hits, :academy) do
    hits
    |> Enum.map(fn chunk ->
      """
      Source marker: [Academy: #{escape_marker_label(chunk.title)}](#{chunk.url})
      Most relevant chunk from article: #{chunk.chunk}
      """
    end)
    |> Enum.join("\n")
  end

  # Insights are dated commentary: an old post's prices, levels and "current"
  # readings are wrong if presented as today's. Surfacing the publish date AND
  # its age lets the answer model judge staleness without doing date arithmetic
  # itself (LLMs are unreliable at it) — it reads "1857 days ago" and treats the
  # post's specific values as stale. Missing dates degrade to "unknown date"
  # rather than silently dropping the line.
  defp published_on(chunk) do
    case chunk_date(chunk) do
      nil -> "unknown date"
      date -> "#{Date.to_iso8601(date)} (#{age_phrase(Date.diff(Date.utc_today(), date))})"
    end
  end

  defp chunk_date(chunk) do
    case Map.get(chunk, :published_at) do
      %NaiveDateTime{} = dt -> NaiveDateTime.to_date(dt)
      %DateTime{} = dt -> DateTime.to_date(dt)
      %Date{} = d -> d
      _ -> nil
    end
  end

  defp age_phrase(days) when days <= 0, do: "today"
  defp age_phrase(1), do: "1 day ago"
  defp age_phrase(days), do: "#{days} days ago"

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

  # Labels (post/article titles, FAQ questions) are user-controlled and get
  # interpolated raw into the `[label](url)` markdown link. Without escaping, a
  # crafted title like `x](https://phish)` closes the label early and injects a
  # different target — the model would then cite a forged/phishing link. Escape
  # the markdown link delimiters (and the backslash itself, first, so we don't
  # double-escape) and fold newlines, so the label can only ever be inert text
  # inside the link.
  defp escape_marker_label(label) do
    label
    |> to_string()
    |> String.replace(~r/[\r\n]+/u, " ")
    |> String.replace("\\", "\\\\")
    |> String.replace("[", "\\[")
    |> String.replace("]", "\\]")
    |> String.replace("(", "\\(")
    |> String.replace(")", "\\)")
  end
end
