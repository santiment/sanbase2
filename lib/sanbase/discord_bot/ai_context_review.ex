defmodule Sanbase.DiscordBot.AiContextReview do
  @moduledoc """
  Finds AI bot turns (Discord and Telegram) worth a human look and exports them.

  Flags are derived from what `ai_context` already stores, so they also apply
  to rows written before the review page existed:

    * `delivery_failed` - the answer was not posted to the chat
    * `error` / `degraded` - no answer, or an answer from a fallback path
    * `tool_issue` - a tool failed or returned nothing (see `tool_issues`)
    * `language_mismatch` - the answer is written in another script than the
      question (e.g. an English question answered in Cyrillic)
    * `downvoted` - a user voted the answer down
    * `slow` - the turn took longer than 60 seconds
  """

  import Ecto.Query

  alias Sanbase.DiscordBot.AiContext
  alias Sanbase.Repo

  @flags ~w(delivery_failed error degraded tool_issue language_mismatch downvoted slow)
  @slow_seconds 60
  # Questions shorter than this are mostly tickers or "hi"; their script says
  # little about the language the user expects.
  @min_letters_for_language 12

  @scripts [
    latin: ~r/\p{Latin}/u,
    cyrillic: ~r/\p{Cyrillic}/u,
    greek: ~r/\p{Greek}/u,
    arabic: ~r/\p{Arabic}/u,
    hebrew: ~r/\p{Hebrew}/u,
    han: ~r/\p{Han}/u,
    hiragana: ~r/\p{Hiragana}/u,
    katakana: ~r/\p{Katakana}/u,
    hangul: ~r/\p{Hangul}/u,
    thai: ~r/\p{Thai}/u,
    devanagari: ~r/\p{Devanagari}/u
  ]

  def flags(), do: @flags

  @doc """
  Turns in `[from, to)`, newest first, each as `%{context: row, flags: [...]}`.

  Options:
    * `:platform` - "discord" | "telegram" | nil for both
    * `:flag` - keep only rows with this flag
    * `:flagged_only` - keep only rows with at least one flag
  """
  def list(from, to, opts \\ []) do
    from
    |> range_query(to, opts[:platform])
    |> Repo.all()
    |> Enum.map(&review_row/1)
    |> Enum.filter(&keep?(&1, opts[:flag], opts[:flagged_only]))
  end

  @doc """
  Parses the review page filters (also used by the export link) from URL
  params. Dates are inclusive days in UTC; the default is yesterday and today.
  """
  def parse_filters(params) do
    today = Date.utc_today()
    to = parse_date(params["to"], today)
    from = parse_date(params["from"], Date.add(to, -1))

    %{
      from: Enum.min([from, to], Date),
      to: to,
      platform:
        if(params["platform"] in ["discord", "telegram"], do: params["platform"], else: ""),
      flag: if(params["flag"] in @flags, do: params["flag"], else: ""),
      flagged_only: params["flagged_only"] != "false"
    }
  end

  @doc """
  All rows in the date range and platform of `filters`, flagged or not. Narrow
  them with `select/2`; the unnarrowed list is what the flag counts come from.
  """
  def list_for_filters(filters) do
    {from, to} = datetime_range(filters)
    list(from, to, platform: filters.platform)
  end

  @doc "Keeps the rows that match the flag filters of `filters`."
  def select(rows, filters), do: Enum.filter(rows, &keep?(&1, filters.flag, filters.flagged_only))

  @doc """
  `list_for_filters/1` narrowed by `select/2`, read in batches so the export
  holds only one batch in memory. Must run inside `Repo.transaction/2`.
  """
  def stream_for_filters(filters) do
    {from, to} = datetime_range(filters)

    from
    |> range_query(to, filters.platform)
    |> Repo.stream(max_rows: 500)
    |> Stream.map(&review_row/1)
    |> Stream.filter(&keep?(&1, filters.flag, filters.flagged_only))
  end

  defp datetime_range(filters) do
    {NaiveDateTime.new!(filters.from, ~T[00:00:00]),
     NaiveDateTime.new!(Date.add(filters.to, 1), ~T[00:00:00])}
  end

  defp range_query(from, to, platform) do
    from(c in AiContext,
      where: c.inserted_at >= ^from and c.inserted_at < ^to,
      order_by: [desc: c.inserted_at, desc: c.id]
    )
    |> filter_platform(platform)
  end

  defp review_row(context), do: %{id: context.id, context: context, flags: flags_for(context)}

  defp parse_date(value, default) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> date
      _ -> default
    end
  end

  defp parse_date(_value, default), do: default

  @doc "Counts per flag for a list returned by `list/3`."
  def flag_counts(rows) do
    counts = rows |> Enum.flat_map(& &1.flags) |> Enum.frequencies()
    Map.new(@flags, &{&1, Map.get(counts, &1, 0)})
  end

  def flags_for(%AiContext{} = context) do
    [
      {"delivery_failed", context.delivery_status == "failed"},
      {"error", context.status == AiContext.error_status()},
      {"degraded", context.status == AiContext.degraded_status()},
      {"tool_issue", (context.tool_issues || []) != []},
      {"language_mismatch", language_mismatch?(context.question, context.answer)},
      {"downvoted", downvoted?(context.votes)},
      {"slow", is_number(context.elapsed_time) and context.elapsed_time > @slow_seconds}
    ]
    |> Enum.filter(&elem(&1, 1))
    |> Enum.map(&elem(&1, 0))
  end

  def platform(%AiContext{guild_id: "tg_" <> _}), do: "telegram"
  def platform(%AiContext{}), do: "discord"

  @doc """
  True when the question and the answer are mainly written in different
  scripts. Script, not language: it catches an English question answered in
  Russian, but not one answered in German.
  """
  def language_mismatch?(question, answer) when is_binary(question) and is_binary(answer) do
    with {question_script, question_letters} when question_letters >= @min_letters_for_language <-
           dominant_script(question),
         {answer_script, _} when not is_nil(answer_script) <- dominant_script(answer) do
      question_script != answer_script
    else
      _ -> false
    end
  end

  def language_mismatch?(_question, _answer), do: false

  defp dominant_script(text) do
    # URLs are Latin whatever the language around them, so leave them out.
    text = String.replace(text, ~r/https?:\/\/\S+/u, "")

    @scripts
    |> Enum.map(fn {script, regex} -> {script, length(Regex.scan(regex, text))} end)
    |> Enum.max_by(&elem(&1, 1))
    |> case do
      {_script, 0} -> {nil, 0}
      result -> result
    end
  end

  defp downvoted?(votes) when is_map(votes),
    do: Enum.any?(votes, fn {_user, vote} -> vote == -1 end)

  defp downvoted?(_votes), do: false

  @doc """
  One JSON object per line, for handing the rows to an agent that has Langfuse
  and code access.
  """
  def to_jsonl(rows), do: Enum.map_join(rows, "", &to_jsonl_line/1)

  def to_jsonl_line(row), do: Jason.encode!(export_row(row)) <> "\n"

  def export_row(%{context: c, flags: flags}) do
    %{
      id: c.id,
      inserted_at: c.inserted_at,
      platform: platform(c),
      user: c.discord_user,
      chat: c.guild_name,
      thread_id: c.thread_id,
      question: c.question,
      rephrased_question: c.rephrased_question,
      answer: c.answer,
      flags: flags,
      status: c.status,
      error_message: c.error_message,
      delivery_status: c.delivery_status,
      delivery_error: c.delivery_error,
      tools_used: c.tools_used,
      tool_issues: c.tool_issues,
      qa_engine: c.qa_engine,
      v2_fallback: c.v2_fallback,
      elapsed_time: c.elapsed_time,
      total_cost: c.total_cost,
      tokens_total: c.tokens_total,
      votes: c.votes,
      langfuse_trace_id: c.langfuse_trace_id
    }
  end

  defp filter_platform(query, "telegram"), do: where(query, [c], like(c.guild_id, "tg_%"))
  defp filter_platform(query, "discord"), do: where(query, [c], not like(c.guild_id, "tg_%"))
  defp filter_platform(query, _platform), do: query

  defp keep?(row, flag, _flagged_only) when flag in @flags, do: flag in row.flags
  defp keep?(row, _flag, true), do: row.flags != []
  defp keep?(_row, _flag, _flagged_only), do: true
end
