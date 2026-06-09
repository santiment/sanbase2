defmodule Sanbase.Knowledge.Context do
  @moduledoc """
  Builds the per-source context text that goes into the answer prompt.

  Shared by the live prompt builder (`Sanbase.Knowledge`) and the offline
  eval harness (`Sanbase.Knowledge.Eval`) so both exercise the *same*
  assembly logic. Keeping a single source of truth here is what lets the
  eval measure "does the assembled context contain the facts needed to
  answer" without drifting from production.

  Each source produces one entry per hit, leading with a `Source [<id>]`
  header that names the source and its label. The numeric id is the ONLY
  thing the answer model has to reproduce to cite a block — it writes the
  bare token `[<id>]` inline and we (`Sanbase.Knowledge.Citations`) expand
  it into a real markdown link from `marker/2`. The model never sees or
  copies a URL, which is what makes citations reliable on a small model:
  copying `[3]` is trivial, copying a long `[Academy: label](https://…)`
  verbatim is not. The id is omitted from the header when a hit carries no
  `:marker_id` (the eval path), so recall measurement is unaffected.

  `marker/2` is the single place that derives a citation's `{prefix, label,
  url}` from a hit, so the prompt header, the inline link, and the grouped
  `Sources` section all agree. `assemble/2` returns the inner text only —
  the caller wraps it in the source's XML tag.

  This module is also the seam where future context expansion (pulling
  neighbor chunks / parent article around a matched chunk) will plug in:
  the hits passed in already carry their text, so an expansion step that
  enriches `:chunk` / `:text_chunk` before assembly is transparent here and
  measurable by the eval's `context_recall`.
  """

  @type source :: :faq | :insight | :academy

  @type marker :: %{source: source(), prefix: String.t(), label: String.t(), url: String.t()}

  @doc """
  Derive the `{source, prefix, label, url}` citation marker for one hit.

  This is the single source of truth for how a hit maps to a citation, used
  by the prompt header here and by link building in
  `Sanbase.Knowledge.Citations`. The label is cleaned (whitespace folded,
  long FAQ questions truncated) but NOT markdown-escaped — escaping happens
  only where the label is interpolated into a `[label](url)` link.
  """
  @spec marker(map(), source()) :: marker()
  def marker(hit, :faq) do
    %{
      source: :faq,
      prefix: "FAQ",
      label: faq_label(hit.question),
      url: "#{SanbaseWeb.Endpoint.admin_url()}/admin/faq/#{hit.id}"
    }
  end

  def marker(hit, :insight) do
    %{
      source: :insight,
      prefix: "Insight",
      label: clean_label(hit.post_title),
      url: SanbaseWeb.Endpoint.insight_url(hit.post_id)
    }
  end

  def marker(hit, :academy) do
    %{
      source: :academy,
      prefix: "Academy",
      label: clean_label(hit.title),
      url: hit.url
    }
  end

  @doc """
  Assemble the inner context text for a list of reranked hits of one source.

  Returns `""` for an empty hit list. Each block leads with a `Source [<id>]`
  header (the id taken from `hit[:marker_id]`, omitted when absent).
  """
  @spec assemble([map()], source()) :: String.t()
  def assemble([], _source), do: ""

  def assemble(hits, :faq) do
    hits
    |> Enum.map(fn entry ->
      """
      #{source_header(entry, :faq)}
      Question: #{entry.question}
      Answer: #{entry.answer_markdown}
      """
    end)
    |> Enum.join("\n")
  end

  def assemble(hits, :insight) do
    hits
    |> Enum.map(fn chunk ->
      """
      #{source_header(chunk, :insight)}
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
      #{source_header(chunk, :academy)}
      Most relevant chunk from article: #{chunk.chunk}
      """
    end)
    |> Enum.join("\n")
  end

  # The header names the block so the model knows what `[<id>]` refers to. The
  # id is what the model copies inline to cite; when a hit carries no
  # `:marker_id` (the eval path) the token is dropped and only the label shows.
  defp source_header(hit, source) do
    %{prefix: prefix, label: label} = marker(hit, source)

    case Map.get(hit, :marker_id) do
      nil -> "Source — #{prefix}: #{label}"
      id -> "Source [#{id}] — #{prefix}: #{label}"
    end
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

  # The label is the citation's visible text, so a FAQ links via its question
  # (its title) rather than the opaque id. Truncated to keep citations short.
  @faq_label_max 100
  defp faq_label(question) do
    cleaned = clean_label(question)

    if String.length(cleaned) > @faq_label_max do
      String.slice(cleaned, 0, @faq_label_max) <> "…"
    else
      cleaned
    end
  end

  # Fold newlines/runs of whitespace so a label is always a single inert line —
  # it goes into a one-line prompt header and into a `[label](url)` link.
  defp clean_label(label) do
    label
    |> to_string()
    |> String.replace(~r/\s+/u, " ")
    |> String.trim()
  end

  @doc """
  Escape markdown link delimiters in a label so it can only ever be inert text
  inside a `[label](url)` link.

  Labels (post/article titles, FAQ questions) are user-controlled. Without
  escaping, a crafted title like `x](https://phish)` would close the label
  early and inject a different target when we build the citation link. Escape
  the backslash first (so we don't double-escape) and then the link delimiters.
  """
  @spec escape_label(String.t()) :: String.t()
  def escape_label(label) do
    label
    |> to_string()
    |> String.replace("\\", "\\\\")
    |> String.replace("[", "\\[")
    |> String.replace("]", "\\]")
    |> String.replace("(", "\\(")
    |> String.replace(")", "\\)")
  end
end
