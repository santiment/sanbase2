defmodule Sanbase.DeepResearch.Timeline do
  @moduledoc """
  Pure state reducer for a research transcript: folds parsed stream events into
  per-turn timeline state (`reduce_timeline`, `upsert_thinking`, `merge_phase`)
  and groups it for rendering (`segment`, `coalesce`).

  Shaping the *finished* report markdown (source reflow, in-report chart specs)
  is a separate concern — see `Sanbase.DeepResearch.ReportMarkdown`.

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
    upsert_by_id(items, :thinking, id, fn _existing ->
      %{kind: :thinking, id: id, text: text}
    end)
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
  # Item kinds that render as their own block type (and so break a tools run);
  # every other kind folds into a `{:tools, items, running?}` block.
  @block_tag %{thinking: :narration, skill: :skill, chart: :chart, subagent_findings: :findings}

  @spec segment([map()]) :: [tuple()]
  def segment(items) do
    {blocks, tools} =
      Enum.reduce(items, {[], []}, fn item, {blocks, tools} ->
        case @block_tag[item.kind] do
          nil -> {blocks, tools ++ [item]}
          tag -> {push_block(flush_tools(blocks, tools), tag, item), []}
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

  # Append to the newest block when it carries the same tag (keeping the run
  # contiguous), otherwise start a new block.
  defp push_block([{tag, items} | rest], tag, item), do: [{tag, items ++ [item]} | rest]
  defp push_block(blocks, tag, item), do: [{tag, [item]} | blocks]

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
end
