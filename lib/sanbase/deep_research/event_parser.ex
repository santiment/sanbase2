defmodule Sanbase.DeepResearch.EventParser do
  @moduledoc """
  Parses one decoded SSE `data:` payload from LangGraph `runs/stream` into a
  normalized result map for the deep research stream.

  The result map carries any of the following optional keys (a single line can
  produce several, e.g. an `:activity` plus a `:phase`):

    * `:run_id`   - the run id (for cancellation), string
    * `:phase`    - phase hint, one of `:planning | :researching | :writing | :awaiting_user`
    * `:report`   - final report markdown (string)
    * `:thinking` - `%{id: String.t(), text: String.t()}` cumulative AI snapshot
    * `:activity` - `%{kind: atom(), ...}` one event from the custom protocol channel
    * `:error`    - terminal error detail (string)
    * `:meta`     - `%{mcp_tool_calls, mcp_configured, mcp_warning}` (subset, from the gateway)

  An empty map means "nothing to apply" (heartbeat / noise / tool message).
  """

  @activity_types ~w(search_query search_results mcp_call mcp_result source skill status report clarification)

  # Internal structured-output field names that can leak onto the messages channel.
  @structured_field_re ~r/need_clarification|allow_clarification|max_researcher|max_concurrent|search_api/i
  # Pure JSON scaffolding (no prose) on the messages channel.
  @json_scaffolding_re ~r/^[\s{}\[\]",:_0-9.\-]+$/

  @spec parse(term()) :: map()
  def parse(value) when is_map(value) do
    cond do
      is_map(value["santiment_meta"]) -> parse_meta(value["santiment_meta"])
      is_binary(value["run_id"]) -> %{run_id: value["run_id"]}
      value["type"] in @activity_types -> parse_activity_event(value)
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

  defp parse_activity_event(%{"type" => "mcp_call"} = obj) do
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

  defp parse_activity_event(%{"type" => "mcp_result"} = obj) do
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

  defp parse_activity_event(%{"type" => "clarification"} = obj) do
    questions =
      case obj["questions"] do
        list when is_list(list) -> list |> Enum.map(&to_string/1) |> Enum.reject(&(&1 == ""))
        _ -> []
      end

    %{phase: :awaiting_user, activity: %{kind: :clarification, questions: questions}}
  end

  # status
  defp parse_activity_event(obj) do
    state = to_string(obj["state"] || "")
    detail = non_blank(obj["detail"])

    base = %{
      activity: %{
        kind: :status,
        state: state,
        detail: detail,
        tools: if(is_list(obj["tools"]), do: obj["tools"], else: nil)
      }
    }

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

      cond do
        String.trim(text) == "" -> %{}
        Regex.match?(@structured_field_re, text) -> %{}
        Regex.match?(@json_scaffolding_re, text) -> %{}
        true -> %{thinking: %{id: message_id(payload) || "msg", text: text}, phase: :researching}
      end
    end
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

  defp put_if(map, _key, falsy) when falsy in [nil, false], do: map
  defp put_if(map, key, value), do: Map.put(map, key, value)
end
