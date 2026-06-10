defmodule Sanbase.Knowledge.QueryPlan do
  @moduledoc """
  Turns a raw Knowledge search query into a structured retrieval plan.

  A natural-language query like "gimme the latest btc article" fuses signals
  that retrieval must handle separately:

    * the **topic** to match semantically ("bitcoin"),
    * a **temporal directive** ("latest" → sort by recency; "last 7 days" → a
      date window), and
    * possibly **no topic at all** ("summarize the latest insights") — a browse
      request where semantic search has nothing to match on.

  Embedding the raw string conflates them: the meta-words ("latest", "article")
  pull the query vector away from real content and the `min_similarity` gate then
  under-performs. This module parses the query once, up front, into:

      %QueryPlan{
        semantic_query: "bitcoin",   # what to embed/search for (meta-words removed)
        has_topic:      true,        # false = browse mode: skip vector search,
                                     # fetch newest insights directly
        sort:           :recency,    # :recency | :relevance
        date_from:      ~D[...],     # inclusive lower bound, or nil
        date_to:        ~D[...]      # inclusive upper bound, or nil
      }

  `Sanbase.Knowledge` embeds `semantic_query`, applies the date bounds to insight
  retrieval (only insights carry a publication date), uses `sort` to decide
  between relevance reranking and recency ordering, and switches to date-ordered
  browse retrieval when `has_topic` is false.

  ## How the plan is produced

    1. `:query_understanding` enabled (default) **and** an LLM is reachable →
       a cheap structured-output LLM call (self-querying, minimal reasoning
       effort). Handles paraphrases, typos and explicit ranges ("since 2023")
       for free. The call runs under a generous hard budget
       (`:plan_timeout_ms`) — a slower plan is acceptable, but genuine API
       trouble must not wait out the client's own 60s × 3-retry policy.
    2. Otherwise → a neutral **pass-through plan**: the raw query embedded
       as-is, relevance sort, no dates. This is also the graceful fallback
       when the LLM call fails or times out — retrieval quality degrades to
       what it was before query understanding existed, never below.

  Relative windows ("last 7 days") are returned by the LLM as a day count and
  resolved into `date_from` **here, in Elixir** — small models are unreliable at
  date arithmetic, so they only extract the number and we do the calendar math.
  Explicit calendar references ("since January 2026") still come back as ISO
  dates.
  """

  require Logger

  @enforce_keys [:semantic_query]
  defstruct semantic_query: nil, has_topic: true, sort: :relevance, date_from: nil, date_to: nil

  @type t :: %__MODULE__{
          semantic_query: String.t(),
          has_topic: boolean(),
          sort: :recency | :relevance,
          date_from: Date.t() | nil,
          date_to: Date.t() | nil
        }

  # Cheap, fast model for the self-query step — independent of the (possibly
  # larger) model that writes the final answer.
  @llm_client Sanbase.OpenAI.Question
  @llm_model "gpt-5-nano"

  # Hard budget for the planning LLM call. The underlying client retries with
  # backoff and a 60s receive timeout — fine for the *answer* call, too long for
  # a pre-retrieval step. Past this budget the pass-through plan is used instead.
  # Deliberately generous: a good plan is worth waiting a few extra seconds for
  # (the call is typically ~1-3s with `reasoning_effort: "minimal"`), so the
  # budget only exists to catch genuine API trouble, not to race the model.
  @plan_timeout_ms 20_000

  # Plan extraction is trivial classification — reasoning tokens only add
  # latency (a default-effort nano call regularly blows multi-second budgets
  # just thinking). Minimal effort keeps the call fast AND cheap.
  @reasoning_effort "minimal"

  @doc """
  Build the retrieval plan for `user_input`.

  Options:

    * `:query_understanding` — use the LLM self-query step (default `true`).
      A neutral pass-through plan (raw query, relevance sort) is used when
      `false`, when no LLM is reachable, or when the call fails.
    * `:plan_llm_client` — module with `ask/2` used for the self-query call
      (default `#{inspect(@llm_client)}`). Injectable for tests.
    * `:plan_timeout_ms` — time budget for the self-query call (default
      `#{@plan_timeout_ms}`); on expiry the pass-through plan is used.
  """
  @spec build(String.t(), keyword()) :: t()
  def build(user_input, options \\ []) when is_binary(user_input) do
    plan = base_plan(user_input, options)

    Logger.info(
      "query_plan: sort=#{plan.sort} has_topic=#{plan.has_topic} " <>
        "date_from=#{plan.date_from} date_to=#{plan.date_to} " <>
        "rewritten=#{plan.semantic_query != user_input} " <>
        "semantic_query=#{inspect(plan.semantic_query)}"
    )

    plan
  end

  @doc """
  Build a plan from an already-decoded LLM JSON map. Public so it can be unit
  tested without a network call. Returns `:error` on a structurally invalid map
  so the caller can fall back to the pass-through plan.

  `today` anchors the resolution of the relative `last_n_days` window; it
  defaults to `Date.utc_today()` and is a parameter only for deterministic tests.

  Normalisation rules:

    * blank/missing `semantic_query` falls back to the raw query;
    * `has_topic: false` forces `sort: :recency` — browsing without a topic is
      only meaningful newest-first;
    * an explicit `date_from` wins over `last_n_days` when the model returns
      both (the explicit date is the more specific extraction).
  """
  @spec parse(map(), String.t(), Date.t()) :: {:ok, t()} | :error
  def parse(map, user_input, today \\ Date.utc_today())

  def parse(map, user_input, %Date{} = today) when is_map(map) do
    has_topic = parse_has_topic(Map.get(map, "has_topic"))
    sort = if has_topic, do: sort(Map.get(map, "sort")), else: :recency

    date_from =
      parse_date(Map.get(map, "date_from")) ||
        resolve_last_n_days(Map.get(map, "last_n_days"), today)

    {:ok,
     %__MODULE__{
       semantic_query: semantic_query(Map.get(map, "semantic_query"), user_input),
       has_topic: has_topic,
       sort: sort,
       date_from: date_from,
       date_to: parse_date(Map.get(map, "date_to"))
     }}
  end

  def parse(_other, _user_input, _today), do: :error

  @doc """
  The plan as a JSON-serialisable, string-keyed map — for persistence
  (`QuestionAnswerLog.query_plan`) and other places a struct can't go.
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = plan) do
    %{
      "semantic_query" => plan.semantic_query,
      "has_topic" => plan.has_topic,
      "sort" => Atom.to_string(plan.sort),
      "date_from" => plan.date_from && Date.to_iso8601(plan.date_from),
      "date_to" => plan.date_to && Date.to_iso8601(plan.date_to)
    }
  end

  @doc """
  The OpenAI-compatible structured-output schema for the self-query call.
  """
  @spec response_format() :: map()
  def response_format() do
    %{
      "type" => "json_schema",
      "json_schema" => %{
        "name" => "knowledge_query_plan",
        "strict" => true,
        "schema" => %{
          "type" => "object",
          "additionalProperties" => false,
          "required" => [
            "semantic_query",
            "has_topic",
            "sort",
            "last_n_days",
            "date_from",
            "date_to"
          ],
          "properties" => %{
            "semantic_query" => %{
              "type" => "string",
              "description" =>
                "The query rewritten to describe ONLY the topic to search for, with meta-words about recency/ordering removed. Faithful to the user's topic; do not add topics they did not mention. Example: 'gimme the latest btc article' -> 'bitcoin'."
            },
            "has_topic" => %{
              "type" => "boolean",
              "description" =>
                "false ONLY when the query asks for recent content generically, with no subject to search for (e.g. 'summarize the latest insights'). true whenever any topic, asset, metric or concept is named."
            },
            "sort" => %{
              "type" => "string",
              "enum" => ["recency", "relevance"],
              "description" =>
                "'recency' if the user wants the newest/latest/most-recent content — including requests to analyze/summarize 'the latest X' (plural counts too); otherwise 'relevance'."
            },
            "last_n_days" => %{
              "type" => ["integer", "null"],
              "description" =>
                "When the query implies a RELATIVE time window, its length in days ('last 7 days' -> 7, 'past month' -> 30, 'past year' -> 365); otherwise null. Do not resolve it to dates yourself."
            },
            "date_from" => %{
              "type" => ["string", "null"],
              "description" =>
                "Inclusive lower bound as an ISO date (YYYY-MM-DD) ONLY for explicit calendar references ('since January 2026' -> 2026-01-01, 'in 2024' -> 2024-01-01); otherwise null. Never use it for relative windows — use last_n_days for those."
            },
            "date_to" => %{
              "type" => ["string", "null"],
              "description" =>
                "Inclusive upper bound as an ISO date (YYYY-MM-DD) ONLY for explicit calendar references ('in 2024' -> 2024-12-31, 'before March 2025' -> 2025-02-28); otherwise null."
            }
          }
        }
      }
    }
  end

  # --- plan construction -------------------------------------------------

  defp base_plan(user_input, options) do
    client = Keyword.get(options, :plan_llm_client, @llm_client)

    if Keyword.get(options, :query_understanding, true) and llm_available?(client) do
      timeout_ms = Keyword.get(options, :plan_timeout_ms, @plan_timeout_ms)

      case llm_plan_with_budget(user_input, client, timeout_ms) do
        {:ok, plan} ->
          plan

        other ->
          Logger.info("query_plan: LLM self-query failed, using pass-through (#{inspect(other)})")

          passthrough_plan(user_input)
      end
    else
      passthrough_plan(user_input)
    end
  end

  # Neutral plan: the raw query embedded as-is, relevance sort, no dates.
  # Used when query understanding is off, no LLM is reachable, or the LLM call
  # fails — retrieval behaves exactly as it did before query understanding.
  defp passthrough_plan(user_input) do
    %__MODULE__{semantic_query: user_input}
  end

  # --- LLM self-query ----------------------------------------------------

  # The default client needs the OpenAI key (read via the client's own
  # accessor); an injected client (tests, future providers) is assumed to
  # manage its own availability.
  defp llm_available?(client) when client == @llm_client do
    case @llm_client.openai_apikey() do
      key when is_binary(key) and key != "" -> true
      _ -> false
    end
  end

  defp llm_available?(_client), do: true

  # Run the self-query under a hard time budget. The client's own retry/backoff
  # (60s receive timeout, 3 attempts) is sized for answer generation; the
  # planning step must degrade to the pass-through plan instead of blocking retrieval.
  # Crashes inside the task are caught and surface as {:error, _} so the caller
  # falls back rather than taking the LiveView process down with the link.
  defp llm_plan_with_budget(user_input, client, timeout_ms) do
    task =
      Task.async(fn ->
        try do
          llm_plan(user_input, client)
        rescue
          error -> {:error, error}
        catch
          kind, reason -> {:error, {kind, reason}}
        end
      end)

    case Task.yield(task, timeout_ms) || Task.shutdown(task, :brutal_kill) do
      {:ok, result} -> result
      nil -> {:error, :plan_timeout}
    end
  end

  defp llm_plan(user_input, client) do
    opts = %{
      model: @llm_model,
      response_format: response_format(),
      reasoning_effort: @reasoning_effort
    }

    with {:ok, content} <- client.ask(prompt(user_input), opts),
         {:ok, map} <- Jason.decode(content) do
      parse(map, user_input)
    end
  end

  defp prompt(user_input) do
    today = Date.to_iso8601(Date.utc_today())

    """
    You convert a knowledge-base search query into a structured retrieval plan.
    Today's date is #{today}.

    Return a JSON object with these keys:
    - semantic_query: the query rewritten to describe ONLY the topic to search
      for, with meta-words about recency or ordering removed. Stay faithful to the
      user's topic; do NOT invent topics they did not mention. If the query is
      already purely topical, return it essentially unchanged.
      Example: "gimme the latest btc article" -> "bitcoin".
    - has_topic: false ONLY when the query asks for recent content generically
      with no subject at all (e.g. "summarize the latest insights", "what's
      new?"). true whenever any topic, asset, metric or concept is named.
    - sort: "recency" if the user wants the newest / latest / most recent content
      — including requests to analyze or summarize "the latest X" (plural counts
      too); otherwise "relevance". A plain "latest"/"newest" with no window is
      sort="recency" and no dates.
    - last_n_days: for RELATIVE time windows, the window length in days
      ("in the last 7 days" -> 7, "past month" -> 30); otherwise null. Do NOT
      convert relative windows to dates yourself.
    - date_from / date_to: ISO dates (YYYY-MM-DD) ONLY for explicit calendar
      references ("since January 2026" -> date_from 2026-01-01; "in 2024" ->
      date_from 2024-01-01, date_to 2024-12-31); otherwise null.

    Examples:
    - "Analyze the latest bitcoin insights" ->
      {"semantic_query": "bitcoin", "has_topic": true, "sort": "recency",
       "last_n_days": null, "date_from": null, "date_to": null}
    - "what is MVRV?" ->
      {"semantic_query": "MVRV", "has_topic": true, "sort": "relevance",
       "last_n_days": null, "date_from": null, "date_to": null}
    - "summarize the latest insights" ->
      {"semantic_query": "insights", "has_topic": false, "sort": "recency",
       "last_n_days": null, "date_from": null, "date_to": null}
    - "eth whale activity in the last 7 days" ->
      {"semantic_query": "ethereum whale activity", "has_topic": true,
       "sort": "recency", "last_n_days": 7, "date_from": null, "date_to": null}

    Output ONLY the JSON object.

    User query:
    #{user_input}
    """
  end

  # --- field parsing -----------------------------------------------------

  defp semantic_query(value, user_input) when is_binary(value) do
    case String.trim(value) do
      "" -> user_input
      trimmed -> trimmed
    end
  end

  defp semantic_query(_value, user_input), do: user_input

  defp parse_has_topic(false), do: false
  defp parse_has_topic(_other), do: true

  defp sort("recency"), do: :recency
  defp sort(_other), do: :relevance

  defp resolve_last_n_days(n, today) when is_integer(n) and n > 0, do: Date.add(today, -n)
  defp resolve_last_n_days(_other, _today), do: nil

  defp parse_date(value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> date
      _ -> nil
    end
  end

  defp parse_date(_value), do: nil
end
