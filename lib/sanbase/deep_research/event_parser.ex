defmodule Sanbase.DeepResearch.EventParser do
  @moduledoc """
  Parses one decoded SSE `data:` payload from LangGraph `runs/stream` into a
  normalized result map for the deep research stream.

  The result map carries any of the following optional keys (a single line can
  produce several, e.g. an `:activity` plus a `:phase`):

    * `:run_id`   - the run id (for cancellation), string; comes with the `metadata`
                    event a worker emits when it picks the run up, so it also carries
                    a `:phase` (out of `:queued`) and a `run_started`/`run_restarted`
                    status row (see `parse_run_metadata/1`)
    * `:phase`    - phase hint, one of `:planning | :researching | :writing | :awaiting_user`
    * `:report`   - final report markdown (string)
    * `:thinking` - `%{id: String.t(), text: String.t()}` cumulative AI snapshot
    * `:live`     - `%{kind: :tool_call_draft, name, chars, preview}`: a tool call the
                    model is still writing (its streamed arguments so far). Not a
                    timeline item — the UI shows it as "what the agent is doing now"
                    and drops it once the call lands.
    * `:activity` - `%{kind: atom(), ...}` one event from the custom protocol channel
                    (search/mcp/fetch calls and results, status rows, the run's usage)
    * `:error`    - terminal error detail (string): a `status: error`, a gateway
                    `stream_error`, or LangGraph's own `error` payload when a run crashes
    * `:meta`     - `%{mcp_tool_calls, mcp_configured, mcp_warning}` (subset, from the gateway)

  An empty map means "nothing to apply" (heartbeat / noise / tool message).
  """

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

  @spec parse(term()) :: map()
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
  def parse(_), do: %{}

  @doc "Parse a thread `state` object (the poll fallback) into a result map."
  @spec parse_thread_state(term()) :: map()
  def parse_thread_state(%{"values" => values}) when is_map(values),
    do: extract_from_values(values)

  def parse_thread_state(_), do: %{}

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

    %{
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

    result = if map_size(mcp) > 0, do: %{meta: mcp}, else: %{}

    # A `stream_error` in the meta is a terminal failure — surface it at the top
    # level so it flows through the same failed-run path as a `status: error`.
    case non_blank(meta["stream_error"]) do
      nil -> result
      err -> Map.put(result, :error, err)
    end
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

    %{error: prefix <> String.slice(message, 0, 600)}
  end

  # -- custom protocol channel events ------------------------------------------

  defp parse_activity_event(%{"type" => "report"} = obj) do
    case non_blank(obj["markdown"]) do
      nil -> %{}
      md -> %{report: md, phase: :writing}
    end
  end

  defp parse_activity_event(%{"type" => "search_query"} = obj) do
    %{
      phase: :researching,
      activity: %{kind: :search_query, id: obj["id"], query: to_string(obj["query"] || "")}
    }
  end

  defp parse_activity_event(%{"type" => "search_results"} = obj) do
    results = parse_results(obj["results"])

    %{
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

    %{
      phase: :researching,
      activity: %{kind: :fetch_call, id: obj["id"], url: to_string(args["url"] || "")}
    }
  end

  defp parse_activity_event(%{"type" => "tool_result", "tool" => "web_fetch"} = obj) do
    %{
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
    %{
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
    %{
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
    %{
      activity: %{
        kind: :source,
        title: obj["title"],
        url: to_string(obj["url"] || ""),
        domain: obj["domain"]
      }
    }
  end

  defp parse_activity_event(%{"type" => "skill"} = obj) do
    %{
      phase: :researching,
      activity: %{kind: :skill, name: to_string(obj["name"] || ""), path: non_blank(obj["path"])}
    }
  end

  defp parse_activity_event(%{"type" => "chart"} = obj) do
    series = if is_list(obj["series"]), do: Enum.filter(obj["series"], &is_map/1), else: []

    if series == [] do
      %{}
    else
      %{
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

    %{
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

    %{phase: :awaiting_user, activity: %{kind: :clarification, questions: questions}}
  end

  # The run's usage ledger, emitted once as the run ends (just before the end
  # `status`, in success and error runs alike). Tokens are the fleet-wide total
  # (orchestrator + sub-agents) when the agent reports one.
  defp parse_activity_event(%{"type" => "usage"} = obj) do
    %{
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
    %{
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

    activity =
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

    base = %{activity: activity}

    # A terminal `error` status means the agent ended a turn WITHOUT a report.
    # Route the reason through the failed-run path so the UI shows an error.
    if state == "error" do
      Map.put(
        base,
        :error,
        detail || non_blank(obj["reason"]) || "Research ended without delivering a report."
      )
    else
      base
    end
  end

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
        %{report: values["final_report"], phase: :writing}

      non_blank(values["research_brief"]) ->
        %{phase: :planning}

      not is_nil(values["notes"]) ->
        %{phase: :researching}

      true ->
        %{}
    end
  end

  defp extract_from_values(_), do: %{}

  # Some `updates` payloads nest the values under a node key:
  # `{"<node>": {"values": {...}}}` or `{"<node>": {"final_report": ...}}`.
  defp parse_node_updates(obj) do
    Enum.find_value(obj, %{}, fn
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

  defp merge_node_hint(node_key, result) do
    if Map.has_key?(result, :phase) do
      result
    else
      k = String.downcase(to_string(node_key))

      cond do
        String.contains?(k, "plan") or String.contains?(k, "brief") ->
          Map.put(result, :phase, :planning)

        String.contains?(k, "research") or String.contains?(k, "search") ->
          Map.put(result, :phase, :researching)

        String.contains?(k, "report") or String.contains?(k, "writ") ->
          Map.put(result, :phase, :writing)

        true ->
          result
      end
    end
  end

  # -- `messages` channel (streamed assistant "thinking" tokens) ---------------

  defp parse_messages(payload) do
    # ONLY AI messages are thinking — tool/human/system messages must not appear.
    if message_type(payload) != "ai" do
      %{}
    else
      text = message_text(payload)

      thinking =
        cond do
          String.trim(text) == "" ->
            %{}

          Regex.match?(@structured_field_re, text) ->
            %{}

          Regex.match?(@json_scaffolding_re, text) ->
            %{}

          Regex.match?(@json_object_re, text) ->
            %{}

          true ->
            %{thinking: %{id: message_id(payload) || "msg", text: text}, phase: :researching}
        end

      case plan_call(payload) do
        nil ->
          case tool_call_draft(payload) do
            nil -> thinking
            draft -> Map.put(thinking, :live, draft)
          end

        todos ->
          # A finished `write_todos` is the plan itself — a timeline item that updates in
          # place (see `Timeline.reduce_timeline/2`), not a tool call to peek at.
          Map.put(thinking, :activity, %{kind: :plan, todos: todos})
      end
    end
  end

  # The todo list of a FINISHED `write_todos` call (parsed args), or nil.
  defp plan_call(payload) do
    with msg when is_map(msg) <- Enum.find(payload, &(is_map(&1) and Map.has_key?(&1, "content"))),
         call when is_map(call) <-
           Enum.find(
             List.wrap(msg["tool_calls"]),
             &(&1["name"] == "write_todos" and is_map(&1["args"]))
           ) do
      todo_list(call["args"]["todos"])
    else
      _ -> nil
    end
  end

  defp todo_list(list) when is_list(list) do
    list
    |> Enum.filter(&is_map/1)
    |> Enum.map(
      &%{content: to_string(&1["content"] || ""), status: to_string(&1["status"] || "pending")}
    )
    |> Enum.reject(&(&1.content == ""))
  end

  defp todo_list(_), do: []

  # Todos recovered from a `write_todos` call whose arguments are still streaming: whole
  # JSON when it already parses, else every complete `{...}` object so far. The item the
  # model is mid-way through writing has no closing brace yet and is left out.
  @todo_object_re ~r/\{[^{}]*\}/
  @todo_content_re ~r/"content"\s*:\s*"((?:[^"\\]|\\.)*)"/
  @todo_status_re ~r/"status"\s*:\s*"(\w+)"/

  defp todos_in("write_todos", args) do
    case Jason.decode(args) do
      {:ok, %{"todos" => list}} ->
        todo_list(list)

      _ ->
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
  end

  defp todos_in(_name, _args), do: []

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

  defp tool_call_draft(payload) do
    with msg when is_map(msg) <- Enum.find(payload, &(is_map(&1) and Map.has_key?(&1, "content"))),
         [_ | _] = calls <- Enum.flat_map(@draft_keys, &List.wrap(msg[&1])),
         call when is_map(call) <- List.last(calls),
         args when args != "" <- draft_args(call["args"]) do
      name = non_blank(call["name"]) || "tool"

      draft = %{
        kind: :tool_call_draft,
        name: name,
        chars: byte_size(args),
        preview: args |> redact_long_strings() |> tail(@draft_preview_chars)
      }

      case todos_in(name, args) do
        [] -> draft
        todos -> Map.put(draft, :todos, todos)
      end
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

  defp put_if(map, _key, falsy) when falsy in [nil, false], do: map
  defp put_if(map, key, value), do: Map.put(map, key, value)
end
