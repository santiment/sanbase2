defmodule SanbaseWeb.KnowledgeAnswerHTML do
  @moduledoc """
  Renders a Knowledge answer (markdown that may carry `{{date:...}}` sentinels)
  to display HTML.

  `Sanbase.Knowledge` (smart-search listings) and `Sanbase.Knowledge.Citations`
  (the Ask AI Sources section) emit insight publication dates inside a
  `{{date:YYYY-MM-DD}}` sentinel rather than as literal markdown, so the date
  span can be styled without letting markdown carry raw HTML.

  Earmark does NOT sanitize: block-level raw HTML (`<script>`, `<img onerror>`)
  and `javascript:` link targets pass through. Answers embed user-generated
  insight titles and LLM output, and are injected with `raw/1`, so the rendered
  HTML is always sanitized first. The sentinel is expanded AFTER sanitizing, so
  the span it produces is our own trusted markup.

  Every surface that displays a Knowledge answer — the live Ask UI and the admin
  history page, which renders the stored answer — must run the same expansion,
  so the contract lives here in exactly one place rather than being duplicated
  per view.
  """

  # Matches ONLY our own emitted dates (an ISO date or the literal "unknown
  # date"), so the captured group substituted into the span can never be
  # attacker-controlled text.
  @date_sentinel ~r/\{\{date:(\d{4}-\d{2}-\d{2}|unknown date)\}\}/

  @doc """
  Render answer markdown to sanitized HTML, expanding `{{date:...}}` sentinels
  into a muted grey, non-wrapping date span. `nil` renders as empty.

  `as_html/1`, not the bang: on a parse error Earmark still returns best-effort
  HTML, which goes through the same sanitizer (never the raw source).
  """
  @spec to_html(String.t() | nil) :: String.t()
  def to_html(answer) do
    {_status, html, _messages} = Earmark.as_html(answer || "")

    html
    |> HtmlSanitizeEx.markdown_html()
    |> String.replace(
      @date_sentinel,
      "<span style=\"color: #9ca3af; white-space: nowrap\">(\\1)</span>"
    )
  end
end
