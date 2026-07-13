defmodule Sanbase.DeepResearch.Timeline do
  @moduledoc """
  Pure state reducer for a research transcript: folds parsed stream events into
  per-turn timeline state (`reduce_timeline`, `upsert_thinking`, `merge_phase`),
  groups it for rendering (`segment`, `coalesce`) and tidies the report
  (`reflow_sources`).

  A transcript is a list of `turn` maps. A turn holds an ordered `timeline` of
  items (thinking / search / mcp / status / skill), accumulated `sources`, the
  final `report`, clarifying `clarification` questions, and a `phase`.

  Item shapes (plain maps keyed by `:kind`):

    * `%{kind: :thinking, id, text}`
    * `%{kind: :search, id, query, count, results}`   (count/results filled in later)
    * `%{kind: :mcp, id, tool, args, ok, summary, done}`
    * `%{kind: :status, state, detail}`
    * `%{kind: :skill, name, path}`
    * `%{kind: :chart, id, slug, range, summary, series}`
  """

  @phases [:idle, :planning, :researching, :writing, :awaiting_user]
  @terminal_phases [:completed, :failed, :cancelled]
  @running_phases [:planning, :researching, :writing]

  @type phase ::
          :idle
          | :planning
          | :researching
          | :writing
          | :awaiting_user
          | :completed
          | :failed
          | :cancelled

  @type turn :: map()

  @doc "A fresh turn for `question`, starting in the `:planning` phase."
  @spec new_turn(String.t(), integer(), non_neg_integer()) :: turn()
  def new_turn(question, id, started_at_ms) do
    %{
      id: id,
      question: question,
      phase: :planning,
      timeline: [],
      sources: [],
      report: nil,
      clarification: nil,
      started_at: started_at_ms,
      finished_at: nil,
      error: nil
    }
  end

  @doc "Is `phase` a terminal (sticky) phase?"
  def terminal_phase?(phase), do: phase in @terminal_phases

  @doc "Is `phase` an in-progress (running) phase?"
  def running_phase?(phase), do: phase in @running_phases

  @doc """
  True when the turn delivered a direct conversational answer — a non-empty
  assistant text message, with no report, no clarification questions, and no
  research tool calls.

  The agent triages every turn: a simple or follow-up question is answered
  briefly in plain text and it deliberately does NOT call `submit_report` (that
  channel is for research reports only). Such a turn emits no `report` event, so
  the absence of a report is expected here, not a failed run. The LiveView uses
  this to avoid the spurious "no report" error on conversational replies. A turn
  that DID research but produced no report is a genuine stall and is excluded.
  """
  @spec direct_answer?(turn()) :: boolean()
  def direct_answer?(turn) do
    is_nil(turn.report) and turn.clarification in [nil, []] and
      not researched?(turn.timeline) and answered_in_text?(turn.timeline)
  end

  defp researched?(timeline), do: Enum.any?(timeline, &(&1.kind in [:search, :mcp]))

  defp answered_in_text?(timeline) do
    Enum.any?(timeline, &(&1.kind == :thinking and String.trim(&1.text || "") != ""))
  end

  @doc """
  Apply one parsed `EventParser` result map to `turn`. A single result may carry
  several effects at once (e.g. report + phase, or activity + phase).
  """
  @spec apply_result(turn(), map()) :: turn()
  def apply_result(turn, result) do
    turn
    |> maybe_report(result)
    |> maybe_thinking(result)
    |> maybe_activity(result)
    |> maybe_phase(result)
    |> maybe_error(result)
  end

  defp maybe_report(turn, %{report: md}) when is_binary(md), do: %{turn | report: md}
  defp maybe_report(turn, _), do: turn

  defp maybe_thinking(turn, %{thinking: %{id: id, text: text}}),
    do: %{turn | timeline: upsert_thinking(turn.timeline, id, text)}

  defp maybe_thinking(turn, _), do: turn

  defp maybe_activity(turn, %{activity: %{kind: :clarification, questions: qs}}),
    do: %{turn | clarification: qs}

  defp maybe_activity(turn, %{activity: %{kind: :source, url: url} = src}) when url != "" do
    if Enum.any?(turn.sources, &(&1.url == url)) do
      turn
    else
      entry = %{url: url, title: src[:title], domain: src[:domain]}
      %{turn | sources: turn.sources ++ [entry]}
    end
  end

  defp maybe_activity(turn, %{activity: activity}),
    do: %{turn | timeline: reduce_timeline(turn.timeline, activity)}

  defp maybe_activity(turn, _), do: turn

  defp maybe_phase(turn, %{phase: phase}), do: %{turn | phase: merge_phase(turn.phase, phase)}
  defp maybe_phase(turn, _), do: turn

  defp maybe_error(turn, %{error: err}) when is_binary(err),
    do: %{turn | phase: :failed, error: err}

  defp maybe_error(turn, _), do: turn

  @doc """
  Fold one activity into the timeline list.

  Search results merge into the matching `search_query` by id; mcp results patch
  the matching `mcp_call` by id; skills dedupe by name.
  """
  @spec reduce_timeline([map()], map()) :: [map()]
  def reduce_timeline(prev, %{kind: :search_query} = a) do
    prev ++ [%{kind: :search, id: a.id, query: a.query}]
  end

  def reduce_timeline(prev, %{kind: :search_results} = a) do
    merged = fn existing ->
      %{
        kind: :search,
        id: a.id,
        query: blank_to(existing && existing.query, a.query),
        count: a.count,
        results: a.results
      }
    end

    upsert_by_id(prev, :search, a.id, merged)
  end

  def reduce_timeline(prev, %{kind: :mcp_call} = a) do
    prev ++ [%{kind: :mcp, id: a.id, tool: a.tool, args: a[:args]}]
  end

  def reduce_timeline(prev, %{kind: :mcp_result} = a) do
    patch = fn existing ->
      base = existing || %{kind: :mcp, id: a.id, tool: a.tool}
      Map.merge(base, %{ok: a.ok, summary: a[:summary], done: true})
    end

    upsert_by_id(prev, :mcp, a.id, patch)
  end

  def reduce_timeline(prev, %{kind: :status, state: state} = a)
      when state in ["mcp_error", "mcp_ready"] do
    prev ++ [%{kind: :status, state: state, detail: a[:detail]}]
  end

  def reduce_timeline(prev, %{kind: :skill, name: name} = a) do
    if Enum.any?(prev, &(&1.kind == :skill and &1.name == name)) do
      prev
    else
      prev ++ [%{kind: :skill, name: name, path: a[:path]}]
    end
  end

  def reduce_timeline(prev, %{kind: :chart} = a) do
    build = fn _existing ->
      %{
        kind: :chart,
        id: a.id,
        slug: a[:slug],
        range: a[:range],
        summary: a[:summary],
        series: a.series
      }
    end

    upsert_by_id(prev, :chart, a.id, build)
  end

  def reduce_timeline(prev, %{kind: :subagent_findings} = a) do
    prev ++
      [
        %{
          kind: :subagent_findings,
          unit: a[:unit],
          summary: a[:summary],
          findings: a[:findings] || [],
          gaps: a[:gaps] || []
        }
      ]
  end

  def reduce_timeline(prev, _), do: prev

  # Find the item of `kind` with `id` and replace it via `fun.(existing)`;
  # if none (or id is nil), append `fun.(nil)`.
  defp upsert_by_id(prev, kind, id, fun) do
    index =
      if is_nil(id),
        do: nil,
        else: Enum.find_index(prev, &(&1.kind == kind and Map.get(&1, :id) == id))

    case index do
      nil -> prev ++ [fun.(nil)]
      i -> List.replace_at(prev, i, fun.(Enum.at(prev, i)))
    end
  end

  defp blank_to(nil, fallback), do: fallback || ""
  defp blank_to("", fallback), do: fallback || ""
  defp blank_to(value, _fallback), do: value

  @doc """
  LangGraph streams CUMULATIVE message snapshots per id, so replace the block for
  that id rather than append (appending snowballs the text).
  """
  @spec upsert_thinking([map()], String.t(), String.t()) :: [map()]
  def upsert_thinking(items, id, text) do
    if Enum.any?(items, &(&1.kind == :thinking and &1.id == id)) do
      Enum.map(items, fn
        %{kind: :thinking, id: ^id} = it -> %{it | text: text}
        it -> it
      end)
    else
      items ++ [%{kind: :thinking, id: id, text: text}]
    end
  end

  @doc """
  Merge a phase hint into the current phase:

    * terminal phases are sticky (never moved by a later update);
    * reaching a terminal phase always wins over the in-progress phases;
    * otherwise advance monotonically through the in-progress order.
  """
  @spec merge_phase(phase(), phase() | nil) :: phase()
  def merge_phase(current, nil), do: current
  def merge_phase(current, current), do: current

  def merge_phase(current, next) do
    cond do
      current in @terminal_phases -> current
      next in @terminal_phases -> next
      phase_index(next) > phase_index(current) -> next
      true -> current
    end
  end

  defp phase_index(phase), do: Enum.find_index(@phases, &(&1 == phase)) || -1

  @doc """
  Split the timeline into ordered blocks for rendering:

    * `{:narration, [thinking_item, ...]}` - contiguous run of thinking (visible prose)
    * `{:tools, [item, ...], running?}`    - contiguous run of search/mcp/status (folded)
    * `{:skill, [skill_item, ...]}`        - contiguous run of skills (always-visible chips)
    * `{:chart, [chart_item, ...]}`        - contiguous run of charts (always-visible widgets)
    * `{:findings, [finding_item, ...]}`   - contiguous run of sub-agent findings (folded tables)
  """
  @spec segment([map()]) :: [tuple()]
  def segment(items) do
    {blocks, tools} =
      Enum.reduce(items, {[], []}, fn item, {blocks, tools} ->
        case item.kind do
          :thinking -> {push_narration(flush_tools(blocks, tools), item), []}
          :skill -> {push_skill(flush_tools(blocks, tools), item), []}
          :chart -> {push_chart(flush_tools(blocks, tools), item), []}
          :subagent_findings -> {push_findings(flush_tools(blocks, tools), item), []}
          _ -> {blocks, tools ++ [item]}
        end
      end)

    blocks
    |> flush_tools(tools)
    |> Enum.reverse()
  end

  # `blocks` is accumulated most-recent-first (head = last block).
  defp flush_tools(blocks, []), do: blocks

  defp flush_tools(blocks, tools),
    do: [{:tools, tools, tools_running?(tools)} | blocks]

  defp push_narration([{:narration, items} | rest], item),
    do: [{:narration, items ++ [item]} | rest]

  defp push_narration(blocks, item), do: [{:narration, [item]} | blocks]

  defp push_skill([{:skill, items} | rest], item), do: [{:skill, items ++ [item]} | rest]
  defp push_skill(blocks, item), do: [{:skill, [item]} | blocks]

  defp push_chart([{:chart, items} | rest], item), do: [{:chart, items ++ [item]} | rest]
  defp push_chart(blocks, item), do: [{:chart, [item]} | blocks]

  defp push_findings([{:findings, items} | rest], item),
    do: [{:findings, items ++ [item]} | rest]

  defp push_findings(blocks, item), do: [{:findings, [item]} | blocks]

  @doc "True if any tool item in the run is still in flight (search awaiting results / mcp not done)."
  @spec tools_running?([map()]) :: boolean()
  def tools_running?(items) do
    Enum.any?(items, fn item ->
      (item.kind == :search and is_nil(Map.get(item, :count))) or
        (item.kind == :mcp and Map.get(item, :done) != true)
    end)
  end

  @doc """
  Coalesce consecutive `:mcp` items into one `{:mcp_group, items}` so a run of
  data-tool/MCP calls renders as a single folded entry, preserving interleaving
  with searches and statuses.
  """
  @spec coalesce([map()]) :: [map() | {:mcp_group, [map()]}]
  def coalesce(items) do
    {out, run} =
      Enum.reduce(items, {[], []}, fn
        %{kind: :mcp} = item, {out, run} -> {out, run ++ [item]}
        item, {out, run} -> {[item | flush_mcp_run(out, run)], []}
      end)

    flush_mcp_run(out, run) |> Enum.reverse()
  end

  defp flush_mcp_run(out, []), do: out
  defp flush_mcp_run(out, run), do: [{:mcp_group, run} | out]

  @doc """
  Force a report's `Sources` section to render one entry per line. Idempotent —
  a no-op when already a list, when there are fewer than two sources, or when
  there is no Sources heading.
  """
  @spec reflow_sources(String.t()) :: String.t()
  def reflow_sources(md) when is_binary(md) do
    case Regex.run(~r/(^|\n)\#{0,6}\s*\**sources\**\s*:?\s*\n/i, md, return: :index) do
      [{start, len} | _] ->
        cut = start + len
        head = binary_part(md, 0, cut)
        tail = binary_part(md, cut, byte_size(md) - cut)
        {sources_block, rest} = split_at_next_heading(tail)
        reflow_tail(md, head, sources_block, rest)

      _ ->
        md
    end
  end

  def reflow_sources(md), do: md

  @chart_fence ~r/```chart[ \t]*\n(.*?)\n?```/s

  @doc """
  Split report markdown into ordered render segments, lifting fenced
  ` ```chart ` blocks out as parsed chart specs:

    * `{:md, text}`    - a markdown run
    * `{:chart, spec}` - `%{type: "pie", title: String.t() | nil, slices: [%{label, value}]}`

  A fenced block whose body is not a valid chart spec is left as markdown, so a
  malformed block degrades to a visible code block rather than vanishing.
  """
  @spec split_charts(String.t()) :: [{:md, String.t()} | {:chart, map()}]
  def split_charts(md) when is_binary(md), do: md |> do_split_charts([]) |> Enum.reverse()
  def split_charts(_), do: []

  defp do_split_charts(md, acc) do
    case Regex.run(@chart_fence, md, return: :index) do
      [{ms, ml}, {gs, gl}] ->
        pre = binary_part(md, 0, ms)
        body = binary_part(md, gs, gl)
        full = binary_part(md, ms, ml)
        rest = binary_part(md, ms + ml, byte_size(md) - ms - ml)

        acc
        |> push_md(pre)
        |> push_chart(body, full)
        |> then(&do_split_charts(rest, &1))

      _ ->
        push_md(acc, md)
    end
  end

  defp push_md(acc, text) do
    if String.trim(text) == "", do: acc, else: [{:md, text} | acc]
  end

  defp push_chart(acc, body, full) do
    case parse_chart_spec(body) do
      {:ok, spec} -> [{:chart, spec} | acc]
      :error -> [{:md, full} | acc]
    end
  end

  defp parse_chart_spec(body) do
    case Jason.decode(String.trim(body)) do
      {:ok, obj} when is_map(obj) -> build_spec(to_string(obj["type"] || "pie"), obj)
      _ -> :error
    end
  end

  defp build_spec("pie", obj) do
    case chart_slices(obj) do
      [] -> :error
      slices -> {:ok, %{type: "pie", title: chart_title(obj), slices: slices}}
    end
  end

  defp build_spec(type, obj) when type in ["line", "area", "spike"] do
    case chart_series(obj) do
      [] ->
        :error

      series ->
        {:ok, %{type: "line", title: chart_title(obj), series: series, spike: chart_spike(obj)}}
    end
  end

  defp build_spec(_type, _obj), do: :error

  defp chart_title(obj) do
    case obj["title"] do
      t when is_binary(t) -> blank_to_nil(String.trim(t))
      _ -> nil
    end
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(s), do: s

  defp chart_slices(obj) do
    raw = obj["slices"] || obj["data"] || []

    if is_list(raw) do
      raw
      |> Enum.map(&one_slice/1)
      |> Enum.reject(&(is_nil(&1) or &1.label == "" or &1.value <= 0))
    else
      []
    end
  end

  defp one_slice(s) when is_map(s) do
    label = to_string(s["label"] || s["name"] || "")

    case s["value"] || s["count"] do
      v when is_number(v) -> %{label: label, value: v}
      _ -> nil
    end
  end

  defp one_slice(_), do: nil

  # `series: [%{label, points: [%{t, v}]}]`, or a flat `points: [...]` (single series).
  defp chart_series(obj) do
    raw =
      cond do
        is_list(obj["series"]) ->
          obj["series"]

        is_list(obj["points"]) ->
          [%{"label" => obj["label"] || obj["metric"], "points" => obj["points"]}]

        true ->
          []
      end

    raw
    |> Enum.map(&one_series/1)
    |> Enum.reject(&(is_nil(&1) or length(&1.points) < 2))
  end

  defp one_series(s) when is_map(s) do
    points =
      case s["points"] do
        list when is_list(list) -> list |> Enum.map(&one_point/1) |> Enum.reject(&is_nil/1)
        _ -> []
      end

    %{label: blank_to_nil(to_string(s["label"] || s["name"] || "")), points: points}
  end

  defp one_series(_), do: nil

  defp one_point(p) when is_map(p) do
    with t when is_number(t) <- num(p["t"] || p["time"] || p["x"]),
         v when is_number(v) <- num(p["v"] || p["value"] || p["y"]) do
      %{t: t, v: v}
    else
      _ -> nil
    end
  end

  defp one_point(_), do: nil

  defp chart_spike(obj) do
    case obj["spike"] do
      %{"from" => f, "to" => t} when is_number(f) and is_number(t) -> %{from: f, to: t}
      _ -> nil
    end
  end

  defp num(n) when is_number(n), do: n
  defp num(_), do: nil

  # The Sources block ends at the next Markdown heading (if any) — anything after
  # it is a separate section and must be left untouched, even if it has citation
  # markers of its own.
  defp split_at_next_heading(tail) do
    case Regex.run(~r/\n\#{1,6}\s/, tail, return: :index) do
      [{h_start, _} | _] ->
        {binary_part(tail, 0, h_start), binary_part(tail, h_start, byte_size(tail) - h_start)}

      _ ->
        {tail, ""}
    end
  end

  defp reflow_tail(md, head, sources_block, rest) do
    markers = length(Regex.scan(~r/\[\d+\]/, sources_block))

    lines_with_marker =
      sources_block |> String.split("\n") |> Enum.count(&Regex.match?(~r/\[\d+\]/, &1))

    entries =
      ~r/\s*(?=\[\d+\]\s)/
      |> Regex.split(sources_block)
      |> Enum.map(&(&1 |> String.replace(~r/^[-*]\s*/, "") |> String.trim()))
      |> Enum.reject(&(&1 == ""))

    # Leave untouched when there are fewer than two sources or it is already
    # one-per-line; otherwise re-bullet each entry.
    if markers < 2 or lines_with_marker >= markers or length(entries) < 2 do
      md
    else
      head <> Enum.map_join(entries, "\n", &"- #{&1}") <> "\n" <> rest
    end
  end
end
