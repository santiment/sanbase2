defmodule Sanbase.DeepResearch.EventParser do
  @moduledoc """
  Parses one decoded SSE `data:` payload from LangGraph `runs/stream` into a
  `Sanbase.DeepResearch.Event` — that module documents what each field means.

  One line can fill several fields (an `:activity` plus a `:phase`). An event with
  none of them filled means "nothing to apply": a heartbeat, stream noise, or a tool
  message. `Event.empty?/1` says so.
  """

  alias Sanbase.DeepResearch.Event

  @activity_types ~w(search_query search_results mcp_call mcp_result tool_call tool_result source skill chart status report clarification subagent_findings usage)

  # Internal structured-output field names that can leak onto the messages channel.
  @structured_field_re ~r/need_clarification|allow_clarification|max_researcher|max_concurrent|search_api/i
  # Pure JSON scaffolding (no prose) on the messages channel.
  @json_scaffolding_re ~r/^[\s{}\[\]",:_0-9.\-]+$/
  # A raw JSON object on the messages channel — typically a sub-agent's findings blob
  # streaming as thinking, optionally wrapped in a ```json fence. The `subagent_findings`
  # event renders it as a folded table, so drop the raw JSON here (also a backstop for an
  # orchestrator JSON leak). Matches: a leading fence/brace, OR the findings array key
  # anywhere (so a fenced or partially-streamed blob is still caught).
  #
  # A leading `[` must be followed by `{` or `"` to count as JSON — otherwise prose that
  # opens with a citation marker (`[1] Source — …`) would be dropped as scaffolding.
  @json_object_re ~r/^\s*`{0,3}\s*(?:json)?\s*(?:\{|\[\s*[{"])|"findings"\s*:\s*\[/

  @spec parse(term()) :: Event.t()
  def parse(value) when is_map(value) do
    cond do
      is_map(value["santiment_meta"]) -> parse_meta(value["santiment_meta"])
      is_binary(value["run_id"]) -> parse_run_metadata(value)
      value["type"] in @activity_types -> parse_activity_event(value)
      stream_error?(value) -> parse_stream_error(value)
      is_map(value["values"]) -> extract_from_values(value["values"])
      true -> parse_node_updates(value)
    end
  end

  def parse(value) when is_list(value), do: parse_messages(value)
  def parse(_), do: %Event{}

  @doc "Parse a thread `state` object (the poll fallback)."
  @spec parse_thread_state(term()) :: Event.t()
  def parse_thread_state(%{"values" => values}) when is_map(values),
    do: extract_from_values(values)

  def parse_thread_state(_), do: %Event{}

  # -- LangGraph `event: metadata` -------------------------------------------------
  #
  # `{"run_id": ..., "attempt": n}` is yielded by the worker that picks the run up, so it
  # is the FIRST data event on a stream: until then the server only sends heartbeats
  # while the run waits in its queue (a busy worker pool, a restarting server). It ends
  # the `:queued` phase — the agent is now running. `attempt` > 1 means the server re-ran
  # the run after a restart (resuming from the last checkpoint): worth its own row.
  defp parse_run_metadata(value) do
    attempt = integer_or_nil(value["attempt"]) || 1

    state = if attempt > 1, do: "run_restarted", else: "run_started"

    %Event{
      run_id: value["run_id"],
      phase: :planning,
      activity: %{kind: :status, state: state, detail: nil, attempt: attempt}
    }
  end

  # -- santiment_meta (optional MCP gateway telemetry injected into the stream) -

  defp parse_meta(meta) do
    mcp =
      %{}
      |> put_if(:mcp_tool_calls, is_integer(meta["mcp_tool_calls"]) && meta["mcp_tool_calls"])
      |> put_if(:mcp_configured, meta["mcp_configured"] == true)
      |> put_if(:mcp_warning, non_blank(meta["mcp_warning"]))

    # A `stream_error` in the meta is a terminal failure — surface it in its own field
    # so it flows through the same failed-run path as a `status: error`.
    %Event{
      meta: if(map_size(mcp) > 0, do: mcp),
      error: non_blank(meta["stream_error"])
    }
  end

  # -- LangGraph `event: error` payloads ----------------------------------------
  #
  # A run that dies on an exception (recursion limit, provider outage) never reaches
  # the agent's end `status`; LangGraph closes the stream with
  # `{"error": "<ExceptionClass>", "message": "<text>"}` — no `type`. Surface it as
  # the turn's error so the UI says what happened instead of the no-report fallback.
  defp stream_error?(value) do
    is_nil(value["type"]) and is_binary(value["error"]) and is_binary(value["message"])
  end

  defp parse_stream_error(value) do
    kind = non_blank(value["error"])
    message = non_blank(value["message"]) || kind || "unknown error"

    prefix =
      if kind && kind != message,
        do: "The research agent failed (#{kind}): ",
        else: "The research agent failed: "

    %Event{error: prefix <> String.slice(message, 0, 600)}
  end

  # -- custom protocol channel events ------------------------------------------

  defp parse_activity_event(%{"type" => "report"} = obj) do
    case non_blank(obj["markdown"]) do
      nil -> %Event{}
      md -> %Event{report: md, phase: :writing}
    end
  end

  defp parse_activity_event(%{"type" => "search_query"} = obj) do
    %Event{
      phase: :researching,
      activity: %{kind: :search_query, id: obj["id"], query: to_string(obj["query"] || "")}
    }
  end

  defp parse_activity_event(%{"type" => "search_results"} = obj) do
    results = parse_results(obj["results"])

    %Event{
      phase: :researching,
      activity: %{
        kind: :search_results,
        id: obj["id"],
        query: obj["query"],
        count: if(is_integer(obj["count"]), do: obj["count"], else: length(results)),
        results: results
      }
    }
  end

  # `web_fetch` (a sub-agent reading a web page) is a page read, not a data-tool
  # call — it gets its own row, keyed by the fetched url.
  defp parse_activity_event(%{"type" => "tool_call", "tool" => "web_fetch"} = obj) do
    args = if is_map(obj["args"]), do: obj["args"], else: %{}

    %Event{
      phase: :researching,
      activity: %{kind: :fetch_call, id: obj["id"], url: to_string(args["url"] || "")}
    }
  end

  defp parse_activity_event(%{"type" => "tool_result", "tool" => "web_fetch"} = obj) do
    %Event{
      activity: %{
        kind: :fetch_result,
        id: obj["id"],
        ok: obj["ok"],
        summary: non_blank(obj["summary"])
      }
    }
  end

  # MCP tools (`mcp_*`) and deployment-specific custom tools (`tool_*`, e.g.
  # `social_messages`) are both data-tool calls — render them the same way so a
  # custom tool's activity is no longer silently dropped.
  defp parse_activity_event(%{"type" => type} = obj) when type in ["mcp_call", "tool_call"] do
    %Event{
      phase: :researching,
      activity: %{
        kind: :mcp_call,
        id: obj["id"],
        tool: to_string(obj["tool"] || ""),
        args: if(is_map(obj["args"]), do: obj["args"], else: nil)
      }
    }
  end

  defp parse_activity_event(%{"type" => type} = obj) when type in ["mcp_result", "tool_result"] do
    %Event{
      activity: %{
        kind: :mcp_result,
        id: obj["id"],
        tool: to_string(obj["tool"] || ""),
        ok: obj["ok"],
        summary: non_blank(obj["summary"])
      }
    }
  end

  defp parse_activity_event(%{"type" => "source"} = obj) do
    %Event{
      activity: %{
        kind: :source,
        title: obj["title"],
        url: to_string(obj["url"] || ""),
        domain: obj["domain"]
      }
    }
  end

  defp parse_activity_event(%{"type" => "skill"} = obj) do
    %Event{
      phase: :researching,
      activity: %{kind: :skill, name: to_string(obj["name"] || ""), path: non_blank(obj["path"])}
    }
  end

  defp parse_activity_event(%{"type" => "chart"} = obj) do
    series = if is_list(obj["series"]), do: Enum.filter(obj["series"], &is_map/1), else: []

    if series == [] do
      %Event{}
    else
      %Event{
        phase: :researching,
        activity: %{
          kind: :chart,
          id: obj["id"],
          slug: non_blank(obj["slug"]),
          range: non_blank(obj["range"]),
          summary: if(is_map(obj["summary"]), do: obj["summary"], else: nil),
          series: series
        }
      }
    end
  end

  defp parse_activity_event(%{"type" => "subagent_findings"} = obj) do
    findings =
      case obj["findings"] do
        list when is_list(list) -> Enum.filter(list, &is_map/1)
        _ -> []
      end

    gaps =
      case obj["gaps"] do
        list when is_list(list) -> list |> Enum.map(&to_string/1) |> Enum.reject(&(&1 == ""))
        _ -> []
      end

    %Event{
      activity: %{
        kind: :subagent_findings,
        unit: non_blank(obj["unit"]),
        summary: non_blank(obj["summary"]),
        findings: findings,
        gaps: gaps
      }
    }
  end

  defp parse_activity_event(%{"type" => "clarification"} = obj) do
    questions =
      case obj["questions"] do
        list when is_list(list) -> list |> Enum.map(&to_string/1) |> Enum.reject(&(&1 == ""))
        _ -> []
      end

    %Event{phase: :awaiting_user, activity: %{kind: :clarification, questions: questions}}
  end

  # The run's usage ledger, emitted once as the run ends (just before the end
  # `status`, in success and error runs alike). Tokens are the fleet-wide total
  # (orchestrator + sub-agents) when the agent reports one.
  defp parse_activity_event(%{"type" => "usage"} = obj) do
    %Event{
      activity: %{
        kind: :usage,
        elapsed_s: number_or_nil(obj["elapsed_s"]),
        tool_calls: integer_or_nil(obj["tool_calls"]),
        model_calls: integer_or_nil(obj["model_calls"]),
        total_tokens:
          integer_or_nil(obj["total_tokens_all_agents"]) || integer_or_nil(obj["total_tokens"]),
        cost_usd: number_or_nil(obj["cost_usd"]),
        subagent_runs: subagent_runs(obj["subagents"])
      }
    }
  end

  # status
  # Heartbeat from the agent right before a model step: not a row, but the thing to show
  # while a non-streaming model produces nothing visible — the answer to "quiet for 3m".
  # Lands in `turn.live` like a tool-call draft, and clears the same way.
  defp parse_activity_event(%{"type" => "status", "state" => "model_call"} = obj) do
    %Event{
      live: %{
        kind: :model_call,
        role: to_string(obj["role"] || "agent"),
        model: non_blank(obj["model"]),
        step: integer_or_nil(obj["step"]),
        unit: non_blank(obj["unit"]),
        after: non_blank(obj["after"]),
        after_chars: integer_or_nil(obj["after_chars"])
      }
    }
  end

  defp parse_activity_event(obj) do
    state = to_string(obj["state"] || "")
    detail = non_blank(obj["detail"])

    %Event{activity: status_activity(obj, state, detail), error: status_error(obj, state, detail)}
  end

  defp status_activity(obj, state, detail) do
    %{
      kind: :status,
      state: state,
      detail: detail,
      tools: if(is_list(obj["tools"]), do: obj["tools"], else: nil)
    }
    # Optional per-state facts the transcript rows quote (see `Timeline`).
    |> put_if(:reason, non_blank(obj["reason"]))
    |> put_if(:repeats, integer_or_nil(obj["repeats"]))
    |> put_if(:tokens_estimate, integer_or_nil(obj["tokens_estimate"]))
    |> put_if(:messages_summarized, integer_or_nil(obj["messages_summarized"]))
  end

  # A terminal `error` status means the agent ended a turn WITHOUT a report. Route the
  # reason through the failed-run path so the UI shows an error.
  defp status_error(obj, "error", detail),
    do: detail || non_blank(obj["reason"]) || "Research ended without delivering a report."

  defp status_error(_obj, _state, _detail), do: nil

  defp parse_results(results) when is_list(results) do
    Enum.map(results, fn r ->
      %{
        title: to_string(r["title"] || r["url"] || ""),
        url: to_string(r["url"] || ""),
        domain: to_string(r["domain"] || ""),
        snippet: non_blank(r["snippet"])
      }
    end)
  end

  defp parse_results(_), do: []

  # `subagents` is `%{role => %{"runs" => n, ...}}`; count the runs across roles.
  defp subagent_runs(subagents) when is_map(subagents) do
    Enum.reduce(subagents, 0, fn
      {_role, %{"runs" => runs}}, acc when is_integer(runs) -> acc + runs
      _, acc -> acc
    end)
  end

  defp subagent_runs(_), do: 0

  # -- `updates` channel state values ------------------------------------------

  defp extract_from_values(values) when is_map(values) do
    cond do
      non_blank(values["final_report"]) ->
        %Event{report: values["final_report"], phase: :writing}

      non_blank(values["research_brief"]) ->
        %Event{phase: :planning}

      not is_nil(values["notes"]) ->
        %Event{phase: :researching}

      true ->
        %Event{}
    end
  end

  defp extract_from_values(_), do: %Event{}

  # Some `updates` payloads nest the values under a node key:
  # `{"<node>": {"values": {...}}}` or `{"<node>": {"final_report": ...}}`.
  defp parse_node_updates(obj) do
    Enum.find_value(obj, %Event{}, fn
      {key, val} when is_map(val) ->
        cond do
          is_map(val["values"]) -> merge_node_hint(key, extract_from_values(val["values"]))
          has_value_field?(val) -> merge_node_hint(key, extract_from_values(val))
          true -> nil
        end

      _ ->
        nil
    end)
  end

  defp has_value_field?(map) do
    Map.has_key?(map, "final_report") or Map.has_key?(map, "research_brief") or
      Map.has_key?(map, "notes")
  end

  defp merge_node_hint(_node_key, %Event{phase: phase} = event) when not is_nil(phase), do: event

  defp merge_node_hint(node_key, event) do
    k = String.downcase(to_string(node_key))

    cond do
      String.contains?(k, "plan") or String.contains?(k, "brief") ->
        %{event | phase: :planning}

      String.contains?(k, "research") or String.contains?(k, "search") ->
        %{event | phase: :researching}

      String.contains?(k, "report") or String.contains?(k, "writ") ->
        %{event | phase: :writing}

      true ->
        event
    end
  end

  # -- `messages` channel (streamed assistant "thinking" tokens) ---------------

  # Not prose: internal structured-output fields, and the raw JSON the model emits while
  # filling a schema.
  @noise_res [@structured_field_re, @json_scaffolding_re, @json_object_re]

  defp parse_messages(payload) do
    # ONLY AI messages are thinking — tool/human/system messages must not appear.
    if message_type(payload) != "ai" do
      %Event{}
    else
      msg = Enum.find(payload, &(is_map(&1) and Map.has_key?(&1, "content")))
      {thinking, phase} = thinking_in(payload)
      {activity, live} = plan_or_draft(msg)

      %Event{thinking: thinking, phase: phase, activity: activity, live: live}
    end
  end

  # The prose in the message and the phase it implies — `{nil, nil}` when it is not
  # prose at all.
  defp thinking_in(payload) do
    text = message_text(payload)

    if String.trim(text) == "" or Enum.any?(@noise_res, &Regex.match?(&1, text)),
      do: {nil, nil},
      else: {%{id: message_id(payload) || "msg", text: text}, :researching}
  end

  # A finished `write_todos` is the plan itself — a timeline item that updates in place
  # (see `Timeline.reduce_timeline/2`), not a tool call to peek at. Any other call the
  # model is still writing is the live draft instead.
  # Returns `{activity, live}` — a plan is one or the other, never both.
  defp plan_or_draft(msg) do
    case plan_call(msg) do
      nil -> {nil, tool_call_draft(msg)}
      todos -> {%{kind: :plan, todos: todos}, nil}
    end
  end

  # The todo list of a FINISHED `write_todos` call (parsed args), or nil.
  defp plan_call(msg) when is_map(msg) do
    msg["tool_calls"]
    |> List.wrap()
    |> Enum.find(&(&1["name"] == "write_todos" and is_map(&1["args"])))
    |> case do
      nil -> nil
      call -> nil_if_empty(todo_list(call["args"]["todos"]))
    end
  end

  defp plan_call(_), do: nil

  defp todo_list(list) when is_list(list) do
    list
    |> Enum.filter(&is_map/1)
    |> Enum.map(
      &%{content: to_string(&1["content"] || ""), status: to_string(&1["status"] || "pending")}
    )
    |> Enum.reject(&(&1.content == ""))
  end

  defp todo_list(_), do: []

  # The plan recovered from a `write_todos` call whose arguments are still streaming:
  # whole JSON when it already parses, else every complete `{...}` object so far. The
  # item the model is mid-way through writing has no closing brace yet and is left out.
  @todo_object_re ~r/\{[^{}]*\}/
  @todo_content_re ~r/"content"\s*:\s*"((?:[^"\\]|\\.)*)"/
  @todo_status_re ~r/"status"\s*:\s*"(\w+)"/

  defp todos_in("write_todos", args) do
    case Jason.decode(args) do
      {:ok, %{"todos" => list}} -> todo_list(list)
      _ -> partial_todo_list(args)
    end
  end

  defp todos_in(_name, _args), do: []

  defp partial_todo_list(args) do
    @todo_object_re
    |> Regex.scan(args)
    |> Enum.map(fn [obj] ->
      %{
        content: json_string(capture(@todo_content_re, obj)),
        status: capture(@todo_status_re, obj) || "pending"
      }
    end)
    |> Enum.reject(&(&1.content in [nil, ""]))
  end

  defp capture(re, s) do
    case Regex.run(re, s) do
      [_, v] -> v
      _ -> nil
    end
  end

  # Undo JSON escapes in a captured string body (`\"`, `\n`, `\u00e9`); raw on failure.
  defp json_string(nil), do: nil

  defp json_string(s) do
    case Jason.decode(~s("#{s}")) do
      {:ok, v} when is_binary(v) -> v
      _ -> s
    end
  end

  # A streamed AI message carries the tool call it is writing as `invalid_tool_calls`
  # (arguments not yet valid JSON) or `tool_call_chunks` (raw fragments); the finished
  # message has them parsed under `tool_calls`. Until the call lands nothing else in
  # the stream moves, so this is the only sign of life during a long tool call — and,
  # since a cheap model can loop for ever inside one, the tail of the arguments is
  # what tells a user whether it is still making progress.
  @draft_keys ~w(tool_calls invalid_tool_calls tool_call_chunks)
  @draft_preview_chars 600

  defp tool_call_draft(msg) when is_map(msg) do
    case streaming_call(msg) do
      nil ->
        nil

      {name, args} ->
        %{
          kind: :tool_call_draft,
          name: name,
          chars: byte_size(args),
          preview: args |> redact_long_strings() |> tail(@draft_preview_chars)
        }
        |> put_if(:todos, nil_if_empty(todos_in(name, args)))
    end
  end

  defp tool_call_draft(_), do: nil

  # The call the message is currently writing, as `{name, arguments so far}` — the last
  # one, since earlier calls in the same message have already landed. Nil when there is
  # none, or when nothing of its arguments has arrived yet.
  defp streaming_call(msg) do
    with [_ | _] = calls <- Enum.flat_map(@draft_keys, &List.wrap(msg[&1])),
         call when is_map(call) <- List.last(calls),
         args when args != "" <- draft_args(call["args"]) do
      {non_blank(call["name"]) || "tool", args}
    else
      _ -> nil
    end
  end

  defp draft_args(args) when is_binary(args), do: args
  defp draft_args(args) when is_map(args) and map_size(args) > 0, do: Jason.encode!(args)
  defp draft_args(_), do: ""

  # Long string values are where the data lives (file contents, code, briefs, and the
  # social messages a run has fetched); the JSON around them is what says what the model
  # is doing. Keep the structure, replace bulky values with their size. The value still
  # being streamed has no closing quote yet and is hidden the same way.
  @draft_value_max_chars 80

  defp redact_long_strings(args), do: redact(args, [])

  defp redact(<<?", rest::binary>>, acc) do
    {value, rest, closed?} = scan_string(rest, [])
    redact(rest, [acc, redacted_value(value, closed?)])
  end

  defp redact(<<c, rest::binary>>, acc), do: redact(rest, [acc, c])
  defp redact(<<>>, acc), do: IO.iodata_to_binary(acc)

  # Consumes up to and including the closing quote. An escape (`\"`, `\\`, `\n`, `\uXXXX`)
  # never closes the string.
  defp scan_string(<<?\\, c, rest::binary>>, acc), do: scan_string(rest, [acc, ?\\, c])
  defp scan_string(<<?", rest::binary>>, acc), do: {IO.iodata_to_binary(acc), rest, true}
  defp scan_string(<<c, rest::binary>>, acc), do: scan_string(rest, [acc, c])
  defp scan_string(<<>>, acc), do: {IO.iodata_to_binary(acc), <<>>, false}

  defp redacted_value(value, closed?) do
    n = String.length(value)

    cond do
      n <= @draft_value_max_chars -> [?", value, if(closed?, do: ?", else: [])]
      closed? -> "[#{n} chars]"
      true -> "[#{n} chars…]"
    end
  end

  defp tail(s, n) do
    if String.length(s) > n, do: "…" <> String.slice(s, -n, n), else: s
  end

  defp message_text(payload) do
    payload
    |> Enum.map(fn
      item when is_map(item) -> if is_binary(item["content"]), do: item["content"], else: ""
      _ -> ""
    end)
    |> Enum.join("")
  end

  defp message_id(payload) do
    Enum.find_value(payload, fn
      item when is_map(item) ->
        if Map.has_key?(item, "content") and is_binary(item["id"]) and item["id"] != "",
          do: item["id"]

      _ ->
        nil
    end)
  end

  defp message_type(payload) do
    Enum.find_value(payload, "", fn
      item when is_map(item) ->
        if Map.has_key?(item, "content") and is_binary(item["type"]), do: item["type"]

      _ ->
        nil
    end)
  end

  # -- helpers -----------------------------------------------------------------

  defp non_blank(s) when is_binary(s) do
    case String.trim(s) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp non_blank(_), do: nil

  defp integer_or_nil(v) when is_integer(v), do: v
  defp integer_or_nil(_), do: nil

  defp number_or_nil(v) when is_number(v), do: v
  defp number_or_nil(_), do: nil

  defp nil_if_empty([]), do: nil
  defp nil_if_empty(list), do: list

  defp put_if(map, _key, falsy) when falsy in [nil, false], do: map
  defp put_if(map, key, value), do: Map.put(map, key, value)
end
