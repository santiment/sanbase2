defmodule Sanbase.Knowledge.RecencyIntent do
  @moduledoc """
  Detects whether a Knowledge query asks for the *newest* / *most recent*
  material, as opposed to the most topically-relevant material.

  Retrieval in `Sanbase.Knowledge` ranks by embedding (cosine) similarity, which
  has no notion of time — "gimme newest btc article" returns whatever is closest
  in vector space, which can be years old. When `detect?/1` is true, the caller
  reorders the similarity-filtered candidates newest-first by publication date
  (see `Sanbase.Knowledge`), so the freshest *relevant* item surfaces.

  Detection is a deliberately high-precision keyword heuristic: a false positive
  reorders a normal query by date and can bury the best match, so the matched set
  is restricted to unambiguous recency cues. Ambiguous words that often mean
  something other than "now" are intentionally excluded — notably "current"
  (e.g. "current ratio") and bare "new"/"now" (e.g. "new metric", "now what").

  Common misspellings of the recency words are matched too (e.g. "latets",
  "recancy"). These are a hand-curated list rather than fuzzy/edit-distance
  matching, on purpose: fuzzy matching would also catch real words a single edit
  away ("recant" ~ "recent", "latent" ~ "latest") and reorder normal queries.

  The public surface is a single `detect?/1`, so a future LLM-based intent
  extractor can replace the heuristic without touching callers.
  """

  # Single recency words, each followed by its common misspellings. Curated, not
  # fuzzy — we omit real words one edit away (e.g. "recant", "latent", "newer").
  # These are plain literals, joined into the regex below as whole-word alternatives.
  @recency_words ~w(
    newest newst newset neweset
    latest latets lastest latset laetst
    recent recnet recetn
    recently recenty recentyl
    recency recancy recensy
    today todya toady
  )

  # Multi-word / numeric recency phrases (regex fragments, no typo variants):
  #   - most recent / up-to-date / "this week|month|year"
  #   - "past|last [N|few] day(s)|week(s)|month(s)|year(s)" — also bare
  #     "last week|month|year". "last <noun>" only matches time nouns, so
  #     "last halving" / "last cycle" do NOT trip it.
  @recency_phrases [
    "most[ -]recent",
    "up[ -]to[ -]date",
    "this (?:week|month|year)",
    "(?:past|last) (?:(?:\\d+|few) )?(?:days?|weeks?|months?|years?)"
  ]

  # Word-boundaried, case-insensitive alternation of all words + phrases above.
  @recency_regex Regex.compile!(
                   "\\b(?:" <> Enum.join(@recency_words ++ @recency_phrases, "|") <> ")\\b",
                   "i"
                 )

  @doc """
  Returns `true` when `query` signals that the user wants the most recent
  content. Non-binary input returns `false`.
  """
  @spec detect?(term()) :: boolean()
  def detect?(query) when is_binary(query), do: Regex.match?(@recency_regex, query)
  def detect?(_), do: false

  @doc """
  Remove the recency cue words/phrases from `query`, returning the remaining
  topical text with whitespace collapsed.

  Used to build the retrieval embedding so meta-words like "latest"/"newest"
  don't dilute the topic vector (e.g. "gimme the latest btc article" -> "gimme
  the btc article"). This is the cheap, no-LLM fallback for query rewriting; the
  LLM path in `Sanbase.Knowledge.QueryPlan` does a fuller rewrite. Falls back to
  the original (trimmed) query when stripping would leave nothing.
  """
  @spec strip(String.t()) :: String.t()
  def strip(query) when is_binary(query) do
    stripped =
      @recency_regex
      |> Regex.replace(query, " ")
      |> String.replace(~r/\s+/, " ")
      |> String.trim()

    if stripped == "", do: String.trim(query), else: stripped
  end
end
