defmodule Sanbase.DeepResearch.Timeline do
  @moduledoc """
  Pure state reducer for a research transcript: folds parsed stream events into
  per-turn state (`reduce_timeline`, `upsert_thinking`, `merge_phase`), settles a
  turn once its run ends (`complete_turn`, `fail_turn`, `cancel_turn`, `pause_turn`)
  and groups it for rendering (`segment`, `coalesce`). Shaping the *finished* report
  markdown is separate — see `Sanbase.DeepResearch.ReportMarkdown`.

  A transcript is a list of `Sanbase.DeepResearch.Turn` structs, each holding an
  ordered `timeline`, accumulated `sources`, the `report`, `clarification`
  questions and a `phase`. Item shapes (plain maps keyed by `:kind`):

    * `%{kind: :thinking, id, text}`
    * `%{kind: :search, id, query, count, results}`   (count/results filled in later)
    * `%{kind: :mcp, id, tool, args, ok, summary, done}`
    * `%{kind: :fetch, id, url, ok, summary, done}`        (a sub-agent reading a web page)
    * `%{kind: :status, state, detail, ...}`               (optional per-state facts, see below)
    * `%{kind: :compaction, state, tokens_estimate, messages_summarized}`
                                                            (state: compacting → compacted)
    * `%{kind: :skill, name, path}`
    * `%{kind: :chart, id, slug, range, summary, series}`
    * `%{kind: :script, id, agent, name, language, code, truncated}`

  The run's usage ledger is NOT one of these — it is one record per turn, not an event
  in the flow, so it lands on `Turn.usage` (see `usage/1`).
  """

  # Status states worth a row in the transcript, with the optional facts each carries:
  # `run_started`/`run_restarted` (attempt — the server's worker picked the run up,
  # or re-ran it after a restart), `loop_*` (repeats), `budget_*` and `revising`
  # (reason, detail). `compacting`/`compacted` build the `:compaction` item instead (see
  # `reduce_timeline/2`). Paired states (`subagent_start`/`subagent_done`), the end
  # `done`/`error` (the footer and error box own those) and states newer than this
  # release are dropped.
  @status_rows ~w(run_started run_restarted mcp_error mcp_ready loop_detected loop_halt runaway_output runaway_halt sandbox_reset budget_soft budget_halt revising)
  @status_facts [:reason, :repeats, :attempt]
  @compaction_facts [:tokens_estimate, :messages_summarized]

  # `:queued` is where every turn starts: submitted to the agent server, no worker has
  # picked it up yet. The run's `metadata` event (its first data event) moves it on, so
  # a turn that never leaves `:queued` never ran any agent code at all.
  @phases [:idle, :queued, :planning, :researching, :writing, :awaiting_user]
  @terminal_phases [:completed, :failed, :cancelled]
  @running_phases [:queued, :planning, :researching, :writing]

  @type phase ::
          :idle
          | :queued
          | :planning
          | :researching
          | :writing
          | :awaiting_user
          | :paused
          | :completed
          | :failed
          | :cancelled

  alias Sanbase.DeepResearch.{Event, Turn}

  @type turn :: Turn.t()

  @doc "A fresh turn for `question`, starting `:queued` (submitted, no worker on it yet)."
  @spec new_turn(String.t(), integer(), non_neg_integer()) :: turn()
  def new_turn(question, id, started_at_ms) do
    %Turn{id: id, question: question, started_at: started_at_ms}
  end

  # -- settling a turn: `finished_at` stamped once, terminal phase never downgraded -

  @doc "Mark a finished run `:completed`; an already settled turn keeps its phase."
  @spec complete_turn(turn(), non_neg_integer()) :: turn()
  def complete_turn(turn, now_ms) do
    phase = if settled_phase?(turn.phase), do: turn.phase, else: :completed

    settle(turn, phase, now_ms)
  end

  @doc "Fail a turn with `reason`, keeping any error it already carries."
  @spec fail_turn(turn(), String.t(), non_neg_integer()) :: turn()
  def fail_turn(turn, reason, now_ms) do
    %{settle(turn, merge_phase(turn.phase, :failed), now_ms) | error: turn.error || reason}
  end

  @doc "Cancel a turn (the user's Stop). One that already has a report completes instead."
  @spec cancel_turn(turn(), non_neg_integer()) :: turn()
  def cancel_turn(%{report: report} = turn, now_ms) when is_binary(report),
    do: complete_turn(turn, now_ms)

  def cancel_turn(turn, now_ms), do: settle(turn, :cancelled, now_ms)

  @doc """
  Park an unfinished turn as `:paused`; a settled one is returned as is. `reason`
  (lost connection, crashed run) is kept alongside the resumable phase, so the UI can
  say what interrupted the turn while still offering Continue. `nil` for the ordinary
  disconnect pause.
  """
  @spec pause_turn(turn(), non_neg_integer(), String.t() | nil) :: turn()
  def pause_turn(turn, now_ms, reason \\ nil) do
    if settled_phase?(turn.phase),
      do: turn,
      else: %{settle(turn, :paused, now_ms) | error: turn.error || reason}
  end

  @doc "Stamp the finish time without settling the phase (a run awaiting its poll)."
  @spec stamp_finished_at(turn(), non_neg_integer()) :: turn()
  def stamp_finished_at(turn, now_ms), do: settle(turn, turn.phase, now_ms)

  # Settling also drops the live preview: nothing is being written any more. `Map.put`
  # rather than update syntax here and below: a runner started before a hot code reload
  # still holds turns built without the `live`/`last_event_at` keys.
  defp settle(turn, phase, now_ms) do
    %{turn | phase: phase, finished_at: turn.finished_at || now_ms}
    |> Map.put(:live, nil)
  end

  # -- phases --------------------------------------------------------------------

  @doc "Every phase a turn can be in, running and terminal."
  @spec all_phases() :: [phase()]
  def all_phases(), do: @phases ++ [:paused] ++ @terminal_phases

  @doc "Is `phase` a terminal (sticky) phase?"
  @spec terminal_phase?(phase()) :: boolean()
  def terminal_phase?(phase), do: phase in @terminal_phases

  @doc """
  Needs no further work: terminal, plus `:awaiting_user` (a finished exchange) and
  `:paused` (interrupted but resumable).
  """
  @spec settled_phase?(phase()) :: boolean()
  def settled_phase?(phase), do: terminal_phase?(phase) or phase in [:awaiting_user, :paused]

  @doc """
  Nothing left in flight to render (terminal or `:paused`), so spinners the run never
  closed can settle. `:awaiting_user` is live, so not inactive.
  """
  @spec inactive_phase?(phase()) :: boolean()
  def inactive_phase?(phase), do: terminal_phase?(phase) or phase == :paused

  @doc "Is `phase` an in-progress (running) phase?"
  def running_phase?(phase), do: phase in @running_phases

  @doc """
  True when the turn delivered a direct conversational answer: assistant text, no
  report, no clarification questions, no research tool calls.

  The agent triages every turn and answers a simple one in plain text without calling
  `submit_report`, so a missing report is expected rather than a failed run — the
  LiveView uses this to suppress the spurious "no report" error. A turn that DID
  research and still produced no report is a genuine stall, and is excluded.
  """
  @spec direct_answer?(turn()) :: boolean()
  def direct_answer?(turn) do
    is_nil(turn.report) and turn.clarification in [nil, []] and
      not researched?(turn.timeline) and answered_in_text?(turn.timeline)
  end

  defp researched?(timeline), do: Enum.any?(timeline, &(&1.kind in [:search, :mcp, :fetch]))

  @doc """
  The run's usage ledger, or nil before the agent reports it. `Map.get`: a runner
  started before a hot code reload holds turns without this key.
  """
  @spec usage(turn()) :: Turn.usage() | nil
  def usage(turn), do: Map.get(turn, :usage)

  defp answered_in_text?(timeline) do
    Enum.any?(timeline, &(&1.kind == :thinking and String.trim(&1.text || "") != ""))
  end

  @doc """
  Apply one parsed `Event` to `turn`; one event may carry several effects (report +
  phase, activity + phase).

  `:at` (stamped by the runner on receipt) becomes `last_event_at`. `:live` — what the
  model is producing right now — replaces the previous preview; any other substantive
  event (text, a tool event, the report) means that draft is finished, so it clears
  the preview instead.
  """
  @spec apply_result(turn(), Event.t()) :: turn()
  def apply_result(turn, %Event{} = event) do
    turn
    |> maybe_report(event)
    |> maybe_thinking(event)
    |> maybe_activity(event)
    |> maybe_phase(event)
    |> maybe_error(event)
    |> maybe_live(event)
    |> stamp_event(event)
  end

  defp maybe_live(turn, %Event{live: live}) when is_map(live), do: Map.put(turn, :live, live)

  defp maybe_live(turn, %Event{thinking: thinking, activity: activity, report: report})
       when not is_nil(thinking) or not is_nil(activity) or not is_nil(report),
       do: Map.put(turn, :live, nil)

  defp maybe_live(turn, _), do: turn

  defp stamp_event(turn, %Event{at: at}) when is_integer(at),
    do: Map.put(turn, :last_event_at, at)

  defp stamp_event(turn, _), do: turn

  defp maybe_report(turn, %Event{report: md}) when is_binary(md), do: %{turn | report: md}
  defp maybe_report(turn, _), do: turn

  defp maybe_thinking(turn, %Event{thinking: %{id: id, text: text}}),
    do: %{turn | timeline: upsert_thinking(turn.timeline, id, text)}

  defp maybe_thinking(turn, _), do: turn

  defp maybe_activity(turn, %Event{activity: %{kind: :clarification, questions: qs}}),
    do: %{turn | clarification: qs}

  defp maybe_activity(turn, %Event{activity: %{kind: :source, url: url} = src}) when url != "" do
    if Enum.any?(turn.sources, &(&1.url == url)) do
      turn
    else
      entry = %{url: url, title: src[:title], domain: src[:domain]}
      %{turn | sources: turn.sources ++ [entry]}
    end
  end

  # One ledger per run; a resumed run reports again and simply replaces it.
  defp maybe_activity(turn, %Event{activity: %{kind: :usage} = ledger}),
    do: Map.put(turn, :usage, drop_nils(Map.delete(ledger, :kind)))

  defp maybe_activity(turn, %Event{activity: activity}) when is_map(activity),
    do: %{turn | timeline: reduce_timeline(turn.timeline, activity)}

  defp maybe_activity(turn, _), do: turn

  defp maybe_phase(turn, %Event{phase: phase}) when not is_nil(phase),
    do: %{turn | phase: merge_phase(turn.phase, phase)}

  defp maybe_phase(turn, _), do: turn

  defp maybe_error(turn, %Event{error: err}) when is_binary(err),
    do: %{turn | phase: :failed, error: err}

  defp maybe_error(turn, _), do: turn

  @doc """
  Fold one activity into the timeline list.

  Search results merge into the matching `search_query` by id; mcp and fetch
  results patch the matching call by id; skills dedupe by name.
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

  def reduce_timeline(prev, %{kind: :fetch_call} = a) do
    prev ++ [%{kind: :fetch, id: a.id, url: a.url}]
  end

  def reduce_timeline(prev, %{kind: :fetch_result} = a) do
    patch = fn existing ->
      base = existing || %{kind: :fetch, id: a.id, url: ""}
      Map.merge(base, %{ok: a.ok, summary: a[:summary], done: true})
    end

    upsert_by_id(prev, :fetch, a.id, patch)
  end

  # Compaction is its own element in the flow: `compacting` opens it (with the context
  # size that triggered it), `compacted` closes the open one with what got summarized. A
  # `compacted` with nothing open (its `compacting` was missed) still gets its element.
  def reduce_timeline(prev, %{kind: :status, state: "compacting"} = a) do
    prev ++ [Map.merge(%{kind: :compaction, state: "compacting"}, facts(a, @compaction_facts))]
  end

  def reduce_timeline(prev, %{kind: :status, state: "compacted"} = a) do
    closed = Map.merge(%{kind: :compaction, state: "compacted"}, facts(a, @compaction_facts))

    case Enum.find_index(prev, &match?(%{kind: :compaction, state: "compacting"}, &1)) do
      nil -> prev ++ [closed]
      i -> List.update_at(prev, i, &Map.merge(&1, closed))
    end
  end

  def reduce_timeline(prev, %{kind: :status, state: state} = a) when state in @status_rows do
    prev ++
      [Map.merge(%{kind: :status, state: state, detail: a[:detail]}, facts(a, @status_facts))]
  end

  # The plan (a finished `write_todos`) is one item that updates in place: the model rewrites
  # the whole list every time a step changes status, and a transcript of six near-identical
  # lists would bury the research. Drafts of it stream through `:live`, not here.
  def reduce_timeline(prev, %{kind: :plan, todos: todos}) do
    item = %{kind: :plan, todos: todos}

    if Enum.any?(prev, &(&1.kind == :plan)),
      do: Enum.map(prev, &if(&1.kind == :plan, do: item, else: &1)),
      else: prev ++ [item]
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

  # One tab per script, updated in place. A worker re-emits a script it edited after a
  # gate bounced its handoff, and two tabs for the same file (draft, then fix) would read
  # as two different scripts. Keyed by agent + name because the event id is fresh on every
  # emit; the FIRST id is kept so the renderer's open/closed DOM state survives the update.
  def reduce_timeline(prev, %{kind: :script} = a) do
    item = %{
      kind: :script,
      id: a[:id] || "sc#{length(prev)}",
      agent: a[:agent],
      name: a[:name],
      language: a[:language],
      code: a[:code],
      truncated: a[:truncated] == true
    }

    same? = &(&1.kind == :script and &1.name == item.name and &1.agent == item.agent)

    case Enum.find_index(prev, same?) do
      nil -> prev ++ [item]
      i -> List.replace_at(prev, i, %{item | id: Enum.at(prev, i).id})
    end
  end

  def reduce_timeline(prev, %{kind: :subagent_findings} = a) do
    prev ++
      [
        %{
          kind: :subagent_findings,
          # No id on the event: stamp the append position, which is immutable, so the
          # renderer keys DOM state on the item, not its drifting screen position.
          id: "sf#{length(prev)}",
          unit: a[:unit],
          summary: a[:summary],
          findings: a[:findings] || [],
          gaps: a[:gaps] || []
        }
      ]
  end

  def reduce_timeline(prev, _), do: prev

  # Replace the `kind`/`id` item via `fun.(existing)`, or append `fun.(nil)`.
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

  # The facts an event carries, minus the ones it left blank.
  defp facts(a, keys), do: a |> Map.take(keys) |> drop_nils()

  defp drop_nils(map), do: Map.reject(map, fn {_k, v} -> is_nil(v) end)

  defp blank_to(nil, fallback), do: fallback || ""
  defp blank_to("", fallback), do: fallback || ""
  defp blank_to(value, _fallback), do: value

  @doc """
  LangGraph streams CUMULATIVE snapshots per id, so replace that id's block rather
  than append — appending snowballs the text.
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
    * `:paused` leaves via a running phase (a resumed run's first events). No
      event moves a turn INTO `:paused`, so it has no phase-order index;
    * otherwise advance monotonically through the in-progress order.
  """
  @spec merge_phase(phase(), phase() | nil) :: phase()
  def merge_phase(current, nil), do: current
  def merge_phase(current, current), do: current
  def merge_phase(:paused, next) when next in @running_phases, do: next

  def merge_phase(current, next) do
    cond do
      current in @terminal_phases -> current
      next in @terminal_phases -> next
      phase_index(next) > phase_index(current) -> next
      true -> current
    end
  end

  defp phase_index(phase), do: Enum.find_index(@phases, &(&1 == phase)) || -1

  # A run of timestamped points pasted into prose: `2026-06-05,-0.2025; 2026-06-06,…` or
  # one pair per line. Six is well past what a sentence quotes and well short of a series.
  @series_point_re ~r/\d{4}-\d{2}-\d{2}[ T]?[\d:]*\s*[,:|]\s*-?[\d.]+(?:[eE][-+]?\d+)?/
  @min_series_points 6

  @doc """
  Split `text` into prose strings and collapsed series runs.

  A run of at least `#{@min_series_points}` timestamped points becomes
  `%{label: "70 daily points, 2026-06-05 → 2026-08-13", text: <the run>}` so the UI can fold
  it behind one line instead of printing a wall of numbers; everything else stays a string.
  A model that summarizes properly never triggers this — it is the safety net for one that
  pastes the series it was told to distill.
  """
  @spec split_series_runs(String.t() | nil) :: [String.t() | map()]
  def split_series_runs(nil), do: []
  def split_series_runs(""), do: []

  def split_series_runs(text) when is_binary(text) do
    case Regex.scan(@series_point_re, text, return: :index) do
      [] -> [text]
      matches -> matches |> Enum.map(fn [span] -> span end) |> group_runs() |> build_parts(text)
    end
  end

  # Consecutive matches separated by at most a delimiter and whitespace belong to one run.
  defp group_runs(spans) do
    spans
    |> Enum.reduce([], fn {start, len} = span, runs ->
      case runs do
        [[{p_start, p_len} | _] = run | rest] when start - (p_start + p_len) <= 3 ->
          [[span | run] | rest]

        _ ->
          [[span] | runs]
      end
    end)
    |> Enum.map(&Enum.reverse/1)
    |> Enum.reverse()
    |> Enum.filter(&(length(&1) >= @min_series_points))
  end

  defp build_parts([], text), do: [text]

  defp build_parts(runs, text) do
    {parts, last} =
      Enum.reduce(runs, {[], 0}, fn run, {parts, cursor} ->
        {first_start, _} = hd(run)
        {last_start, last_len} = List.last(run)
        run_end = last_start + last_len
        prose = binary_part(text, cursor, first_start - cursor)
        body = binary_part(text, first_start, run_end - first_start)
        {[%{label: run_label(run, text), text: body}, prose | parts], run_end}
      end)

    [binary_part(text, last, byte_size(text) - last) | parts]
    |> Enum.reverse()
    |> Enum.reject(&(&1 == ""))
  end

  defp run_label(run, text) do
    {first_start, first_len} = hd(run)
    {last_start, last_len} = List.last(run)
    first = text |> binary_part(first_start, first_len) |> point_date()
    last = text |> binary_part(last_start, last_len) |> point_date()
    "#{length(run)} points, #{first} → #{last} (collapsed)"
  end

  defp point_date(point) do
    case Regex.run(~r/\d{4}-\d{2}-\d{2}/, point) do
      [d] -> d
      _ -> "?"
    end
  end

  @doc """
  Split the timeline into ordered blocks for rendering:

    * `{:narration, [thinking_item, ...]}` - contiguous run of thinking (visible prose)
    * `{:tools, [item, ...], running?}`    - contiguous run of search/mcp/status (folded)
    * `{:skill, [skill_item, ...]}`        - contiguous run of skills (always-visible chips)
    * `{:plan, [plan_item]}`                - the todo list, latest version (always visible)
    * `{:chart, [chart_item, ...]}`        - contiguous run of charts (always-visible widgets)
    * `{:script, [script_item, ...]}`      - contiguous run of scripts (folded code tabs)
    * `{:findings, [finding_item, ...]}`   - contiguous run of sub-agent findings (folded tables)
    * `{:compaction, [compaction_item]}`   - the agent rewriting its own memory (always visible)
  """
  # Kinds that render as their own block, breaking a tools run; the rest fold into
  # `{:tools, items, running?}`.
  @block_tag %{
    thinking: :narration,
    skill: :skill,
    plan: :plan,
    chart: :chart,
    script: :script,
    subagent_findings: :findings,
    compaction: :compaction
  }

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

  # Same tag as the newest block appends (keeping the run contiguous), else new block.
  defp push_block([{tag, items} | rest], tag, item), do: [{tag, items ++ [item]} | rest]
  defp push_block(blocks, tag, item), do: [{tag, [item]} | blocks]

  @doc "True if any tool item in the run is still in flight (search awaiting results / mcp or fetch not done)."
  @spec tools_running?([map()]) :: boolean()
  def tools_running?(items) do
    Enum.any?(items, fn item ->
      (item.kind == :search and is_nil(Map.get(item, :count))) or
        (item.kind in [:mcp, :fetch] and Map.get(item, :done) != true)
    end)
  end

  @doc """
  Coalesce consecutive `:mcp` items into one `{:mcp_group, items}`, so a run of data
  tool calls folds into a single entry while keeping its place among searches.
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
