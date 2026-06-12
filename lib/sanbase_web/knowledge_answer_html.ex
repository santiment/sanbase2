defmodule SanbaseWeb.KnowledgeAnswerHTML do
  @moduledoc """
  Renders a Knowledge answer (markdown that may carry `{{date:...}}` sentinels)
  to display HTML.

  `Sanbase.Knowledge` (smart-search listings) and `Sanbase.Knowledge.Citations`
  (the Ask AI Sources section) emit insight publication dates inside a
  `{{date:YYYY-MM-DD}}` sentinel rather than as literal markdown. This keeps
  Earmark's HTML-escaping ON for user-generated insight titles (no XSS) while
  still letting us style our own date string — so the sentinel must be expanded
  AFTER markdown rendering.

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
  Render answer markdown to HTML, expanding `{{date:...}}` sentinels into a
  muted grey, non-wrapping date span. `nil` renders as empty.
  """
  @spec to_html(String.t() | nil) :: String.t()
  def to_html(answer) do
    (answer || "")
    |> Earmark.as_html!()
    |> String.replace(
      @date_sentinel,
      "<span style=\"color: #9ca3af; white-space: nowrap\">(\\1)</span>"
    )
  end
end
