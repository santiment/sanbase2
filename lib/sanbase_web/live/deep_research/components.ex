defmodule SanbaseWeb.DeepResearch.Components do
  @moduledoc """
  Presentation for `SanbaseWeb.DeepResearchLive` — everything from a turn bubble
  down to a single MCP call row, plus the view helpers those components need.

  Only `composer/1`, `turn_view/1` and `sidebar/1` are public; they are the
  seams the LiveViews' own `render/1` reach for. Everything else is an
  implementation detail of a turn's rendering.

  Nothing here touches the socket or issues events beyond `phx-click`/`phx-submit`
  names, so a component can be rendered in isolation from a plain turn map.
  """
  use SanbaseWeb, :html

  alias Phoenix.LiveView.JS
  alias Sanbase.DeepResearch.{ReportMarkdown, Timeline}
  alias SanbaseWeb.DeepResearch.ChartRenderer

  attr :query, :string, required: true
  attr :running, :boolean, required: true
  attr :placeholder, :string, required: true

  @doc "The question input: auto-growing textarea plus send / stop buttons."
  def composer(assigns) do
    ~H"""
    <form id="dr-composer" phx-submit="submit" phx-change="update_query">
      <div class="flex items-end gap-2 rounded-[1.75rem] border border-base-300 bg-base-100 py-1.5 pl-4 pr-2 shadow-sm transition focus-within:border-base-content/25 focus-within:shadow-md">
        <textarea
          id="dr-composer-input"
          name="query"
          rows="1"
          phx-hook="AutoGrow"
          phx-debounce="150"
          disabled={@running}
          placeholder={@placeholder}
          class="max-h-72 min-h-[2.75rem] flex-1 resize-none overflow-y-auto bg-transparent py-2.5 text-[15px] leading-relaxed placeholder:text-base-content/40 focus:outline-none disabled:opacity-60"
        >{@query}</textarea>
        <div class="flex items-center gap-1 pb-1">
          <button
            :if={@running}
            type="button"
            phx-click="cancel"
            aria-label="Stop research"
            class="flex size-9 items-center justify-center rounded-full text-base-content/50 transition hover:bg-base-200 hover:text-error"
          >
            <.icon name="hero-stop" class="size-4" />
          </button>
          <button
            type="submit"
            aria-label="Send"
            disabled={@running or String.trim(@query) == ""}
            class="flex size-9 items-center justify-center rounded-full bg-primary text-primary-content transition hover:opacity-90 disabled:cursor-not-allowed disabled:opacity-30"
          >
            <.icon name="hero-arrow-up" class="size-4" />
          </button>
        </div>
      </div>
    </form>
    """
  end

  attr :sessions, :list, required: true, doc: "the user's sessions, most recent first"
  attr :current_session_id, :string, default: nil

  @doc """
  Past-sessions sidebar: open / share / delete a session, start a new one.
  Navigation stays enabled mid-run — leaving only detaches from the runner.
  """
  def sidebar(assigns) do
    ~H"""
    <aside class="hidden w-72 shrink-0 flex-col lg:flex">
      <button
        type="button"
        phx-click="new_session"
        class="mb-3 inline-flex cursor-pointer items-center justify-center gap-2 rounded-xl border border-base-300 bg-base-100 px-3 py-2 text-sm font-medium text-base-content/80 transition hover:border-base-content/20 hover:bg-base-200"
      >
        <.icon name="hero-plus" class="size-4" /> New session
      </button>

      <p :if={@sessions == []} class="px-1 text-xs text-base-content/40">
        Past research sessions will appear here.
      </p>

      <div class="min-h-0 flex-1 space-y-1 overflow-y-auto pr-1">
        <%!-- The whole row opens the session (a title-only click target is too
              easy to miss); the action icons carry their own phx-click, and
              LiveView dispatches to the closest binding only, so they do not
              also open it. select-none: a fast double click must not start a
              text selection instead of navigating. --%>
        <div
          :for={session <- @sessions}
          phx-click="open_session"
          phx-value-id={session.id}
          title={session.title}
          class={[
            "group cursor-pointer select-none rounded-xl border px-3 py-2 transition",
            if(session.id == @current_session_id,
              do: "border-primary/40 bg-primary/5",
              else: "border-transparent hover:border-base-300 hover:bg-base-200/60"
            )
          ]}
        >
          <p class="truncate text-sm text-base-content/80">{session.title}</p>
          <div class="mt-1 flex flex-wrap items-center gap-x-1.5 gap-y-1 text-[11px] text-base-content/40">
            <span class="whitespace-nowrap">
              {Calendar.strftime(session.updated_at, "%b %d, %H:%M")}
            </span>
            <span class="whitespace-nowrap rounded-full bg-base-200 px-1.5 py-0.5">
              {session.model_tier}
            </span>
            <span
              :if={session.is_public}
              class="whitespace-nowrap rounded-full bg-success/10 px-1.5 py-0.5 text-success"
            >
              public
            </span>
            <span class="ml-auto flex items-center opacity-0 transition group-hover:opacity-100 group-focus-within:opacity-100">
              <button
                type="button"
                phx-click="toggle_public"
                phx-value-id={session.id}
                title={if session.is_public, do: "Make private", else: "Share (logged-in users)"}
                class={[
                  "cursor-pointer rounded p-1 transition hover:bg-base-200",
                  if(session.is_public, do: "text-success", else: "hover:text-base-content")
                ]}
              >
                <.icon
                  name={if session.is_public, do: "hero-lock-open", else: "hero-lock-closed"}
                  class="size-3.5"
                />
              </button>
              <%!-- Copying is handled client-side by the Copy hook; the empty
                    JS command claims the click so it does not bubble into the
                    row's open_session. --%>
              <button
                :if={session.is_public}
                type="button"
                id={"copy-share-link-#{session.id}"}
                phx-hook="Copy"
                phx-click={%JS{}}
                data-copy={SanbaseWeb.Endpoint.admin_url() <> "/deep_research/shared/#{session.id}"}
                title="Copy share link"
                class="cursor-pointer rounded p-1 transition hover:bg-base-200 hover:text-base-content"
              >
                <.icon name="hero-link" class="size-3.5 [.copied_&]:hidden" />
                <.icon
                  name="hero-check"
                  class="hidden size-3.5 text-success [.copied_&]:inline-block"
                />
              </button>
              <button
                type="button"
                phx-click="delete_session"
                phx-value-id={session.id}
                data-confirm="Delete this research session? This cannot be undone."
                title="Delete session"
                class="cursor-pointer rounded p-1 transition hover:bg-base-200 hover:text-error"
              >
                <.icon name="hero-trash" class="size-3.5" />
              </button>
            </span>
          </div>
        </div>
      </div>
    </aside>
    """
  end

  attr :turn, :map, required: true
  attr :running, :boolean, required: true

  attr :now_ms, :integer,
    default: nil,
    doc:
      "wall clock for the live elapsed counter; nil for a finished turn, whose own finished_at is authoritative"

  attr :can_continue, :boolean,
    default: false,
    doc: "offer Continue on a :paused turn (owner, last turn, nothing running)"

  @doc "One question/answer exchange: the asked question, its research timeline, and any error."
  def turn_view(assigns) do
    ~H"""
    <div class="space-y-4">
      <div class="flex justify-end">
        <div class="max-w-[80%] break-words rounded-2xl rounded-br-sm bg-primary px-4 py-2.5 text-sm leading-relaxed text-primary-content">
          {@turn.question}
        </div>
      </div>

      <.research_timeline
        turn={@turn}
        running={@running}
        now_ms={@now_ms}
        can_continue={@can_continue}
      />

      <.clarification_card
        :if={@turn.clarification && @turn.clarification != []}
        questions={@turn.clarification}
      />

      <.turn_error :if={@turn.error} turn={@turn} />
    </div>
    """
  end

  attr :turn, :map, required: true

  # `:paused` is resumable (lost connection, crashed run) with a Continue right above
  # it — a warning, not the red of research going nowhere.
  defp turn_error(assigns) do
    assigns = assign(assigns, :resumable?, assigns.turn.phase == :paused)

    ~H"""
    <div
      class={[
        "flex items-start gap-2 rounded-xl border px-4 py-3 text-sm",
        if(@resumable?,
          do: "border-warning/30 bg-warning/5 text-warning",
          else: "border-error/30 bg-error/5 text-error"
        )
      ]}
      role={if @resumable?, do: "status", else: "alert"}
    >
      <.icon
        name={if @resumable?, do: "hero-pause-circle", else: "hero-exclamation-triangle"}
        class="mt-0.5 size-4 shrink-0"
      />
      <span>{@turn.error}</span>
    </div>
    """
  end

  attr :questions, :list, required: true

  defp clarification_card(assigns) do
    ~H"""
    <div class="rounded-xl border border-amber-300/50 bg-amber-50/70 p-4 dark:border-amber-500/30 dark:bg-amber-500/10">
      <div class="mb-2 flex items-center gap-2 text-sm font-semibold text-amber-900 dark:text-amber-200">
        <.icon name="hero-question-mark-circle" class="size-4" /> A couple of clarifying questions
      </div>
      <ul class="space-y-1.5 text-sm text-base-content/80">
        <li :for={question <- @questions} class="flex gap-2">
          <span class="mt-2 size-1.5 shrink-0 rounded-full bg-amber-400"></span>
          <span>{question}</span>
        </li>
      </ul>
      <p class="mt-3 text-xs text-base-content/50">Reply below to continue.</p>
    </div>
    """
  end

  attr :turn, :map, required: true
  attr :running, :boolean, required: true
  attr :now_ms, :integer, default: nil
  attr :can_continue, :boolean, default: false

  defp research_timeline(assigns) do
    turn = assigns.turn
    proc_items = visible_items(turn.timeline, turn.report, turn.clarification)
    # Nothing in flight: an item left marked running would spin forever.
    proc_items =
      if Timeline.inactive_phase?(turn.phase),
        do: Enum.map(proc_items, &settle_item/1),
        else: proc_items

    blocks = Timeline.segment(proc_items)
    has_research = Enum.any?(blocks, &match?({:tools, _, _}, &1)) or not is_nil(turn.report)

    assigns =
      assign(assigns,
        blocks: blocks,
        has_research: has_research,
        usage: Timeline.usage(turn),
        empty?: proc_items == [] and is_nil(turn.report)
      )

    ~H"""
    <%!-- A paused turn renders even when empty, to keep Continue reachable; a failed
    one, to say how long it ran before it died. --%>
    <div
      :if={not (@empty? and not @running) or @turn.phase in [:paused, :failed]}
      class="space-y-3"
    >
      <%= for {block, index} <- Enum.with_index(@blocks) do %>
        <.timeline_block block={block} index={index} turn_id={@turn.id} />
      <% end %>

      <.report_card :if={@turn.report} id={@turn.id} report={@turn.report} />

      <%!-- A running *phase* after the stream closed (@running false) is the
      no-report poll window — the turn is still being resolved, keep the
      spinner up rather than freezing the timeline footerless. --%>
      <div :if={@running or Timeline.running_phase?(@turn.phase)} class="space-y-1.5 text-xs">
        <div class="flex flex-wrap items-center gap-x-2 gap-y-1 font-medium text-base-content/60">
          <span class="loading loading-spinner loading-xs text-primary"></span>
          <span>{phase_label(@turn.phase)} · {format_duration(elapsed_seconds(@turn, @now_ms))}</span>
          <.liveness turn={@turn} now_ms={@now_ms} />
        </div>
        <.live_draft :if={Map.get(@turn, :live)} live={@turn.live} turn_id={@turn.id} />
      </div>
      <div
        :if={((not @running and @turn.started_at) && @has_research) and @turn.phase == :completed}
        class="flex items-center gap-1.5 text-xs text-base-content/50"
      >
        <.icon name="hero-check-circle" class="size-3.5 text-success" />
        Researched in {format_duration(elapsed_seconds(@turn, @now_ms, @usage))}
        <.run_stats usage={@usage} />
      </div>
      <div
        :if={@turn.phase == :cancelled and @has_research}
        class="flex items-center gap-1.5 text-xs text-base-content/40"
      >
        <.icon name="hero-no-symbol" class="size-3.5" />
        Stopped after {format_duration(elapsed_seconds(@turn, @now_ms, @usage))}
        <.run_stats usage={@usage} />
      </div>
      <%!-- Always for a failed turn, research or not: the run time is the one fact
      the no-report fallback and a mid-run crash can still report. --%>
      <div
        :if={@turn.phase == :failed and not @running}
        class="flex items-center gap-1.5 text-xs text-base-content/50"
      >
        <.icon name="hero-x-circle" class="size-3.5 text-error" />
        Failed after {format_duration(elapsed_seconds(@turn, @now_ms, @usage))}
        <.run_stats usage={@usage} />
      </div>
      <div
        :if={@turn.phase == :paused}
        class="flex items-center gap-2 text-xs text-base-content/50"
      >
        <.icon name="hero-pause-circle" class="size-3.5 text-warning" />
        <span>Research paused — the connection was lost while it was running.</span>
        <button
          :if={@can_continue}
          type="button"
          phx-click="continue_turn"
          phx-value-id={@turn.id}
          class="inline-flex cursor-pointer items-center gap-1 rounded-full border border-primary/40 bg-primary/10 px-2.5 py-1 text-xs font-medium text-primary transition hover:bg-primary/20"
        >
          <.icon name="hero-play" class="size-3" /> Continue
        </button>
      </div>
    </div>
    """
  end

  # Silence thresholds. The agent gives every model call a 3-minute timeout, so past that
  # a quiet stream is abnormal; past 10 minutes nothing legitimate is still coming and the
  # user should Stop. Under 20 seconds is the normal token-to-token rhythm.
  @fresh_ms 20_000
  @quiet_ms 180_000
  @stalled_ms 600_000

  attr :turn, :map, required: true
  attr :now_ms, :integer, default: nil

  # How long since the run last delivered anything (a token, a tool event), coloured by
  # how abnormal the silence is. Before the first event it counts from the question.
  defp liveness(%{now_ms: nil} = assigns), do: ~H""

  defp liveness(assigns) do
    turn = assigns.turn
    # `Map.get`: a runner started before a hot code reload holds turns without this key.
    last_event_at = Map.get(turn, :last_event_at)
    # Before the first event, count from the question.
    ago_ms = max(assigns.now_ms - (last_event_at || turn.started_at), 0)
    {tone, text} = liveness_state(last_event_at, ago_ms)

    assigns = assign(assigns, tone: tone, text: text)

    ~H"""
    <span class={["inline-flex items-center gap-1.5 font-normal", liveness_text_class(@tone)]}>
      <span class={["size-1.5 rounded-full", liveness_dot_class(@tone)]}></span>
      {@text}
    </span>
    """
  end

  defp liveness_state(last_event_at, ago_ms) do
    ago = format_duration(div(ago_ms, 1000))

    cond do
      ago_ms >= @stalled_ms -> {:dead, "no events for #{ago} — looks stalled, Stop and retry"}
      is_nil(last_event_at) and ago_ms < @quiet_ms -> {:ok, "no events yet"}
      is_nil(last_event_at) -> {:warn, "no events yet, #{ago}"}
      ago_ms < @fresh_ms -> {:live, "last event #{ago} ago"}
      ago_ms < @quiet_ms -> {:ok, "last event #{ago} ago"}
      true -> {:warn, "quiet for #{ago}"}
    end
  end

  defp liveness_text_class(:live), do: "text-success"
  defp liveness_text_class(:ok), do: "text-base-content/50"
  defp liveness_text_class(:warn), do: "text-warning"
  defp liveness_text_class(:dead), do: "text-error"

  defp liveness_dot_class(:live), do: "bg-success animate-pulse"
  defp liveness_dot_class(:ok), do: "bg-base-content/30"
  defp liveness_dot_class(:warn), do: "bg-warning"
  defp liveness_dot_class(:dead), do: "bg-error"

  attr :live, :map, required: true
  attr :turn_id, :any, required: true

  # What the model is producing right now: the tool call whose arguments are still
  # streaming. Nothing else in the transcript moves during it, so this is the one place a
  # user can see progress (the size grows) or a runaway loop (the tail repeats). The
  # preview toggles client-side; JS commands survive LiveView patches, so it stays open.
  # A model is generating and nothing streams yet (a non-streaming model shows its whole
  # message at once when done). Says who and on what, so a long silence has a name.
  defp live_draft(%{live: %{kind: :model_call}} = assigns) do
    ~H"""
    <div class="rounded-lg border border-base-300 bg-base-200/40 px-3 py-2 text-base-content/70">
      <div class="flex items-center gap-2">
        <.icon name="hero-cpu-chip" class="size-3.5 shrink-0 animate-pulse text-primary" />
        <span class="font-medium">
          {role_label(@live.role)} is thinking<span :if={@live.model}>
            on <code class="font-mono">{@live.model}</code>
          </span><span :if={@live.step}>
            · step {@live.step}</span>…
        </span>
      </div>
      <div :if={@live[:unit]} class="mt-1 truncate text-xs text-base-content/60" title={@live.unit}>
        Working on: {@live.unit}
      </div>
      <div :if={@live[:after]} class="mt-0.5 text-xs text-base-content/60">
        Reading what <code class="font-mono">{@live.after}</code>
        returned<span :if={@live[:after_chars]}>
          ({format_kb(@live.after_chars)})
        </span>
      </div>
    </div>
    """
  end

  defp live_draft(assigns) do
    ~H"""
    <div class="rounded-lg border border-base-300 bg-base-200/40 px-3 py-2 text-base-content/70">
      <button
        type="button"
        phx-click={JS.toggle(to: "#live-draft-#{@turn_id}")}
        class="flex w-full cursor-pointer items-center gap-2 text-left"
      >
        <.icon name="hero-pencil-square" class="size-3.5 shrink-0 text-primary" />
        <span :if={@live.name == "write_todos"} class="font-medium">
          Updating the plan · {length(@live[:todos] || [])} steps so far
        </span>
        <span :if={@live.name != "write_todos"} class="font-medium">
          Preparing a <code class="font-mono">{@live.name}</code> call
          · {format_kb(@live.chars)} so far
        </span>
        <span class="ml-auto text-[11px] text-base-content/40">show the raw call</span>
      </button>
      <.todo_list :if={@live[:todos]} todos={@live.todos} />
      <pre
        id={"live-draft-#{@turn_id}"}
        class="mt-2 hidden max-h-48 overflow-auto whitespace-pre-wrap break-all rounded bg-base-100 p-2 font-mono text-[11px] leading-snug"
      >{@live.preview}</pre>
    </div>
    """
  end

  attr :todos, :list, required: true

  # The agent's todo list as a checklist: done / in progress / pending.
  defp todo_list(assigns) do
    ~H"""
    <ul class="mt-2 space-y-1 text-sm">
      <li :for={todo <- @todos} class="flex items-start gap-2">
        <.icon
          name={todo_icon(todo.status)}
          class={"mt-0.5 size-4 shrink-0 #{todo_icon_class(todo.status)}"}
        />
        <span class={todo_text_class(todo.status)}>{todo.content}</span>
      </li>
    </ul>
    """
  end

  defp todo_icon("completed"), do: "hero-check-circle"
  defp todo_icon("in_progress"), do: "hero-arrow-right-circle"
  defp todo_icon(_), do: "hero-minus-circle"

  defp todo_icon_class("completed"), do: "text-success"
  defp todo_icon_class("in_progress"), do: "text-primary"
  defp todo_icon_class(_), do: "text-base-content/30"

  defp todo_text_class("completed"), do: "text-base-content/50 line-through"
  defp todo_text_class("in_progress"), do: "font-medium text-base-content"
  defp todo_text_class(_), do: "text-base-content/70"

  defp role_label("orchestrator"), do: "The orchestrator"
  defp role_label("research-subagent"), do: "A research sub-agent"
  defp role_label("extract-subagent"), do: "The extract sub-agent"
  defp role_label("coding-subagent"), do: "The coding sub-agent"
  defp role_label(role), do: "The #{role}"

  defp format_kb(chars) when chars < 1024, do: "#{chars} B"
  defp format_kb(chars), do: "#{:erlang.float_to_binary(chars / 1024, decimals: 1)} KB"

  attr :usage, :map, default: nil, doc: "the turn's usage ledger (`Timeline.usage/1`), or nil"

  # The agent's own ledger for the run — tool calls, fleet-wide tokens, sub-agent runs
  # and cost — as trailing " · " facts. Nothing for turns from before the agent
  # reported usage, or for a run that died before it could.
  defp run_stats(assigns) do
    assigns = assign(assigns, :parts, usage_parts(assigns.usage))

    ~H"""
    <span :for={part <- @parts} class="text-base-content/40">· {part}</span>
    """
  end

  defp usage_parts(nil), do: []

  defp usage_parts(usage) do
    calls = usage[:tool_calls]
    tokens = usage[:total_tokens]
    runs = usage[:subagent_runs]
    cost = usage[:cost_usd]

    []
    |> append_if(positive?(calls), "#{calls} tool #{pluralize(calls, "call", "calls")}")
    |> append_if(positive?(tokens), "#{format_tokens(tokens || 0)} tokens")
    |> append_if(positive?(runs), "#{runs} sub-agent #{pluralize(runs, "run", "runs")}")
    |> append_if(positive?(cost), format_cost(cost || 0))
  end

  defp positive?(n), do: is_number(n) and n > 0

  defp format_tokens(n) when n >= 1_000_000, do: "#{Float.round(n / 1_000_000, 1)}M"
  defp format_tokens(n) when n >= 1_000, do: "#{div(n, 1_000)}k"
  defp format_tokens(n), do: Integer.to_string(n)

  defp format_cost(cost) when cost < 0.01, do: "<$0.01"
  defp format_cost(cost), do: "$" <> :erlang.float_to_binary(cost / 1, decimals: 2)

  attr :block, :any, required: true
  attr :index, :integer, required: true
  attr :turn_id, :any, default: nil

  defp timeline_block(%{block: {:narration, items}} = assigns) do
    assigns = assign(assigns, :items, items)

    ~H"""
    <div class="space-y-2 text-sm leading-relaxed text-base-content/80">
      <div :for={item <- @items} class="prose prose-sm max-w-none">
        {markdown(item.text)}
      </div>
    </div>
    """
  end

  # The latest plan only — the reducer keeps one item and replaces it in place.
  defp timeline_block(%{block: {:plan, items}} = assigns) do
    assigns = assign(assigns, :plan, List.last(items))

    ~H"""
    <div class="rounded-lg border border-base-300 bg-base-200/40 px-3 py-2">
      <div class="flex items-center gap-2 text-sm font-medium text-base-content/80">
        <.icon name="hero-list-bullet" class="size-4 text-primary" /> Plan
      </div>
      <.todo_list todos={@plan.todos} />
    </div>
    """
  end

  defp timeline_block(%{block: {:skill, items}} = assigns) do
    assigns = assign(assigns, :items, items)

    ~H"""
    <div class="flex flex-wrap gap-1.5">
      <span
        :for={skill <- @items}
        title={"Applied skill: #{skill[:path] || skill.name}"}
        class="inline-flex items-center gap-1.5 rounded-full border border-base-300 bg-violet-500/5 px-2.5 py-1 text-xs text-base-content/80"
      >
        <.icon name="hero-sparkles" class="size-3.5 text-violet-500" /> Skill:
        <span class="font-medium">{skill.name}</span>
      </span>
    </div>
    """
  end

  defp timeline_block(%{block: {:chart, items}} = assigns) do
    assigns = assign(assigns, :items, items)

    ~H"""
    <div class="space-y-3">
      <div
        :for={{chart, ci} <- Enum.with_index(@items)}
        id={stable_dom_id("dra-chart", @turn_id, chart, "#{@index}-#{ci}")}
        phx-hook="LightweightChart"
        phx-update="ignore"
        data-chart={
          Jason.encode!(%{
            slug: chart[:slug],
            range: chart[:range],
            summary: chart[:summary],
            series: chart.series
          })
        }
        class="overflow-hidden rounded-xl border border-base-300 bg-base-100"
      >
        <div class="flex items-center gap-2 border-b border-base-300 px-3.5 py-2 text-xs font-medium text-base-content/60">
          <.icon name="hero-chart-bar" class="size-4 text-primary" />
          <span class="text-base-content/80">{chart_caption(chart)}</span>
        </div>
        <div class="dra-chart-canvas w-full" style="height: 18rem;"></div>
      </div>
    </div>
    """
  end

  # The code a worker wrote, folded. This is the ONLY place a script surfaces: no role
  # names a script path in prose (the path is a dead end — the sandbox dies with the run),
  # so the tab is what the reader opens when they want to check how a number was produced.
  defp timeline_block(%{block: {:script, items}} = assigns) do
    assigns = assign(assigns, :items, items)

    ~H"""
    <div class="space-y-2">
      <details
        :for={{s, si} <- Enum.with_index(@items)}
        id={stable_dom_id("dra-script", @turn_id, s, "#{@index}-#{si}")}
        phx-hook="KeepDetailsOpen"
        class="group rounded-lg border border-base-300 bg-emerald-500/5"
      >
        <summary class="flex cursor-pointer list-none items-center gap-2 px-3 py-2 text-sm text-base-content/80 hover:text-base-content">
          <.icon name="hero-code-bracket" class="size-4 shrink-0 text-emerald-500" />
          <span class="font-medium">View script</span>
          <span class="truncate text-xs text-base-content/50">· {s.name}</span>
          <span class="ml-auto shrink-0 text-xs text-base-content/50">
            {script_lines(s)} {pluralize(script_lines(s), "line", "lines")}
          </span>
          <.icon
            name="hero-chevron-down"
            class="size-4 shrink-0 text-base-content/40 transition-transform group-open:rotate-0 -rotate-90"
          />
        </summary>
        <div class="border-t border-base-300">
          <pre class="overflow-x-auto px-3 py-2.5 text-xs leading-relaxed"><code class={"language-#{s.language}"}>{s.code}</code></pre>
          <p :if={s[:truncated]} class="px-3 pb-2 text-xs text-warning">
            Cut off — the script was too long to send in full.
          </p>
        </div>
      </details>
    </div>
    """
  end

  defp timeline_block(%{block: {:findings, items}} = assigns) do
    assigns = assign(assigns, :items, items)

    ~H"""
    <div class="space-y-2">
      <details
        :for={{f, fi} <- Enum.with_index(@items)}
        id={stable_dom_id("dra-findings", @turn_id, f, "#{@index}-#{fi}")}
        phx-hook="KeepDetailsOpen"
        class="group rounded-lg border border-base-300 bg-indigo-500/5"
      >
        <summary class="flex cursor-pointer list-none items-center gap-2 px-3 py-2 text-sm text-base-content/80 hover:text-base-content">
          <.icon name="hero-clipboard-document-list" class="size-4 shrink-0 text-indigo-500" />
          <span class="font-medium">Sub-agent findings</span>
          <span :if={f[:unit]} class="truncate text-xs text-base-content/50">· {f[:unit]}</span>
          <span class="ml-auto shrink-0 text-xs text-base-content/50">
            {length(f.findings)} {pluralize(length(f.findings), "finding", "findings")}
          </span>
          <.icon
            name="hero-chevron-down"
            class="size-4 shrink-0 text-base-content/40 transition-transform group-open:rotate-0 -rotate-90"
          />
        </summary>
        <div class="space-y-2 border-t border-base-300 px-3 py-2.5">
          <p :if={f[:summary]} class="text-sm text-base-content/80">
            <.series_text text={f[:summary]} />
          </p>
          <div :if={f.findings != []} class="overflow-x-auto">
            <table class="w-full text-xs">
              <thead>
                <tr class="text-left text-base-content/50">
                  <th class="py-1 pr-3 font-medium">Finding</th>
                  <th class="py-1 pr-3 font-medium">Evidence</th>
                  <th class="py-1 font-medium">Source</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={row <- f.findings} class="border-t border-base-200 align-top">
                  <td class="py-1 pr-3">
                    <.series_text text={finding_field(row, ~w(finding observation claim))} />
                  </td>
                  <td class="py-1 pr-3 text-base-content/70">
                    <.series_text text={finding_field(row, ~w(evidence data value))} />
                  </td>
                  <td class="py-1 text-base-content/60">{finding_field(row, ~w(source))}</td>
                </tr>
              </tbody>
            </table>
          </div>
          <p :if={f.gaps != []} class="text-xs text-warning">Gaps: {Enum.join(f.gaps, "; ")}</p>
        </div>
      </details>
    </div>
    """
  end

  # Compaction gets its own element rather than a line inside the research fold: it is
  # the one moment the agent rewrites its own memory, worth seeing at a glance.
  defp timeline_block(%{block: {:compaction, items}} = assigns) do
    assigns = assign(assigns, :items, items)

    ~H"""
    <div
      :for={c <- @items}
      class="flex items-center gap-2 rounded-xl border border-dashed border-base-300 bg-base-200/30 px-3.5 py-2.5 text-xs text-base-content/60"
    >
      <.status_icon
        status={compaction_status(c)}
        class={if(c.state == "compacting", do: "text-primary")}
        interrupted_title="Interrupted — the summary never landed"
      />
      <span class="font-medium text-base-content/80">{compaction_title(c)}</span>
      <span class="text-base-content/50">· {compaction_detail(c)}</span>
    </div>
    """
  end

  defp timeline_block(%{block: {:tools, items, running}} = assigns) do
    assigns =
      assign(assigns,
        items: items,
        running: running,
        status: group_status(items),
        summary: tool_summary(items)
      )

    ~H"""
    <details class="group rounded-xl border border-base-300 bg-base-200/30" open={@running}>
      <summary class="flex cursor-pointer list-none items-center gap-2 rounded-xl px-3.5 py-2.5 text-xs font-medium text-base-content/60 hover:text-base-content">
        <.status_icon status={@status} class={if(@status == :running, do: "text-primary")} />
        <span class="text-base-content/80">Research</span>
        <span class="text-base-content/50">· {@summary}</span>
        <.icon
          name="hero-chevron-down"
          class="ml-auto size-4 text-base-content/40 transition-transform group-open:rotate-0 -rotate-90"
        />
      </summary>
      <div class="space-y-3 border-t border-base-300 px-3.5 py-3">
        <%= for {item, i} <- Enum.with_index(Timeline.coalesce(@items)) do %>
          <.tool_item item={item} index={i} dom_id={tool_dom_id(@turn_id, item, "#{@index}-#{i}")} />
        <% end %>
      </div>
    </details>
    """
  end

  # Hooked (KeepDetailsOpen) and phx-update="ignore" elements key client-side state on
  # their DOM id, so the id must follow the ITEM: a positional index shifts when a block
  # appears mid-run and silently rebinds that state elsewhere. Position is the fallback for
  # id-less items (rows persisted before ids were stamped).
  defp stable_dom_id(prefix, turn_id, %{id: id}, _fallback) when not is_nil(id),
    do: "#{prefix}-#{turn_id}-#{String.replace(to_string(id), ~r/\s+/, "-")}"

  defp stable_dom_id(prefix, turn_id, _item, fallback), do: "#{prefix}-#{turn_id}-#{fallback}"

  # A group only grows at its tail, so its head call is a stable identity.
  defp tool_dom_id(turn_id, {:mcp_group, [first | _]}, fallback),
    do: stable_dom_id("dra-tools", turn_id, first, fallback)

  defp tool_dom_id(turn_id, _item, fallback), do: "dra-tools-#{turn_id}-#{fallback}"

  attr :item, :any, required: true
  attr :index, :integer, required: true
  attr :dom_id, :string, default: nil

  defp tool_item(%{item: {:mcp_group, items}} = assigns) do
    assigns = assign(assigns, items: items, status: group_status(items))

    ~H"""
    <details id={@dom_id} phx-hook="KeepDetailsOpen" class="group">
      <summary class="flex cursor-pointer list-none items-center gap-2 text-sm text-base-content/80 hover:text-base-content">
        <.icon name="hero-circle-stack" class="size-4 text-indigo-500" />
        <span class="font-medium">Data tools</span>
        <span class="text-xs text-base-content/60">
          · {length(@items)} {pluralize(length(@items), "call", "calls")}
        </span>
        <.status_icon status={@status} size="size-3.5" class="ml-auto" />
        <.icon
          name="hero-chevron-down"
          class="size-4 transition-transform group-open:rotate-0 -rotate-90"
        />
      </summary>
      <div class="ml-6 mt-1.5 space-y-1.5">
        <.mcp_call_row :for={call <- @items} call={call} />
      </div>
    </details>
    """
  end

  defp tool_item(%{item: %{kind: :search}} = assigns) do
    ~H"""
    <div class="space-y-1.5">
      <div class="flex items-center gap-2 text-sm text-base-content/80">
        <.icon name="hero-globe-alt" class="size-4 shrink-0 text-base-content/60" />
        <span class="truncate">{@item.query}</span>
        <span :if={Map.get(@item, :count)} class="ml-auto shrink-0 text-xs text-base-content/60">
          {@item.count} results
        </span>
        <span :if={is_nil(Map.get(@item, :count))} class="loading loading-spinner loading-xs ml-auto"></span>
      </div>
      <div
        :if={Map.get(@item, :results) not in [nil, []]}
        class="ml-6 grid grid-cols-1 gap-x-4 gap-y-1 sm:grid-cols-2"
      >
        <.search_result :for={result <- Enum.take(@item.results, 8)} result={result} />
      </div>
    </div>
    """
  end

  defp tool_item(%{item: %{kind: :fetch}} = assigns) do
    url = assigns.item[:url] || ""

    assigns =
      assign(assigns,
        status: call_status(assigns.item),
        href: safe_http_url(url),
        domain: url_domain(url),
        output: assigns.item[:summary]
      )

    ~H"""
    <details class="text-sm">
      <summary class="flex cursor-pointer list-none items-center gap-2 text-base-content/80">
        <.icon name="hero-document-text" class="size-4 shrink-0 text-base-content/60" />
        <span class="shrink-0">Read page</span>
        <.link
          :if={@href}
          href={@href}
          target="_blank"
          rel="noopener noreferrer"
          title={@href}
          class="flex items-center gap-1.5 overflow-hidden text-xs text-base-content/60 hover:text-base-content"
        >
          <.favicon domain={@domain} />
          <span class="truncate">{@domain}</span>
        </.link>
        <span :if={!@href} class="truncate text-xs text-base-content/60">{@domain}</span>
        <.status_icon
          status={@status}
          size="size-3.5"
          class="ml-auto"
          interrupted_title="Interrupted — did not return"
        />
      </summary>
      <pre
        :if={@output}
        class="ml-6 mt-1 max-h-32 overflow-auto whitespace-pre-wrap rounded bg-base-300/40 p-2 text-[11px] text-base-content/60"
      >{@output}</pre>
    </details>
    """
  end

  defp tool_item(%{item: %{kind: :status}} = assigns) do
    assigns = assign(assigns, :label, status_label(assigns.item))

    ~H"""
    <p class={["text-xs", status_class(@item.state)]}>{@label}</p>
    """
  end

  defp tool_item(assigns), do: ~H""

  defp attempt_note(n) when is_integer(n), do: " (attempt #{n})"
  defp attempt_note(_), do: ""

  defp status_class("mcp_error"), do: "text-error"
  defp status_class("run_restarted"), do: "text-warning"

  defp status_class(state) when state in ["loop_halt", "runaway_halt", "budget_halt"],
    do: "text-warning"

  defp status_class(_state), do: "text-base-content/60"

  # One line per agent status row. Only the states `Timeline` keeps reach here, but
  # an older row's state is quoted rather than crashed on.
  defp status_label(%{state: "mcp_error"} = s),
    do: "MCP error: #{s[:detail] || "connection failed"}"

  defp status_label(%{state: "mcp_ready"}), do: "Connected to data tools"

  defp status_label(%{state: "run_started"}),
    do: "Agent server picked up the run — the agent is now working"

  defp status_label(%{state: "run_restarted"} = s),
    do:
      "Agent server restarted the run#{attempt_note(s[:attempt])} — resuming from its last checkpoint"

  defp status_label(%{state: "loop_detected"} = s),
    do:
      "Noticed the same tool call repeating#{times(s[:repeats])} — nudged the agent to change approach"

  defp status_label(%{state: "loop_halt"} = s),
    do: "Stopped: the agent kept repeating the same tool call#{times(s[:repeats])}"

  defp status_label(%{state: "runaway_output"} = s),
    do:
      "Cut off runaway output (#{s[:detail] || "the model repeated itself"}) — nudged the agent to continue"

  defp status_label(%{state: "runaway_halt"} = s),
    do: "Stopped: runaway output again (#{s[:detail] || "the model repeated itself"})"

  defp status_label(%{state: "sandbox_reset"} = s),
    do:
      "Sandbox session was lost mid-run (#{s[:detail] || "timed out"}) — opened a fresh one; files written earlier are gone"

  defp status_label(%{state: "budget_soft"} = s),
    do: s[:detail] || "Approaching the run budget#{budget_kind(s[:reason])} — wrapping up"

  defp status_label(%{state: "budget_halt"} = s),
    do: s[:detail] || "Run budget exhausted#{budget_kind(s[:reason])} — stopping"

  defp status_label(%{state: "revising"} = s) do
    what =
      case s[:reason] do
        "report_quality" -> "the report"
        "subagent_findings" -> "a sub-agent's findings"
        _ -> "the output"
      end

    "Revising #{what}" <> if(s[:detail], do: ": #{s[:detail]}", else: "")
  end

  defp status_label(%{state: state} = s) when is_binary(state),
    do: s[:detail] || String.replace(state, "_", " ")

  defp status_label(s), do: s[:detail] || "status"

  defp times(n) when is_integer(n) and n > 1, do: " (#{n}×)"
  defp times(_), do: ""

  defp compaction_status(%{state: "compacting"}), do: :running
  defp compaction_status(%{state: "compacted"}), do: :ok
  defp compaction_status(_), do: :interrupted

  defp compaction_title(%{state: "compacting"}), do: "Compacting context"
  defp compaction_title(%{state: "compacted"}), do: "Compacted context"
  defp compaction_title(_), do: "Compaction interrupted"

  defp compaction_detail(%{state: "compacting"} = c) do
    case c[:tokens_estimate] do
      n when is_integer(n) and n > 0 ->
        "working context near #{format_tokens(n)} tokens — summarizing the earlier messages"

      _ ->
        "summarizing the earlier messages"
    end
  end

  defp compaction_detail(%{state: "compacted"} = c) do
    what =
      case c[:messages_summarized] do
        n when is_integer(n) -> "summarized #{n} earlier #{pluralize(n, "message", "messages")}"
        _ -> "summarized the earlier messages"
      end

    "#{what}#{tokens_note(c[:tokens_estimate])} into a shorter working context"
  end

  defp compaction_detail(_), do: "the run stopped before the summary landed"

  defp tokens_note(n) when is_integer(n) and n > 0, do: " (~#{format_tokens(n)} tokens)"
  defp tokens_note(_), do: ""

  defp budget_kind("tool_calls"), do: " for tool calls"
  defp budget_kind("tokens"), do: " for tokens"
  defp budget_kind(_), do: ""

  defp url_domain(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{host: host} when is_binary(host) and host != "" -> host
      _ -> url
    end
  end

  defp url_domain(_), do: ""

  attr :result, :map, required: true

  # A non-http(s) URL still shows its title, just not as a link; the label markup is
  # shared so the branches cannot drift.
  defp search_result(assigns) do
    assigns = assign(assigns, :href, safe_http_url(assigns.result.url))

    ~H"""
    <.link
      :if={@href}
      href={@href}
      target="_blank"
      rel="noopener noreferrer"
      title={"#{@result.title} — #{@href}"}
      class="flex items-center gap-1.5 overflow-hidden text-xs text-base-content/60 hover:text-base-content"
    >
      <.search_result_label result={@result} />
    </.link>
    <span
      :if={!@href}
      title={@result.title}
      class="flex items-center gap-1.5 overflow-hidden text-xs text-base-content/60"
    >
      <.search_result_label result={@result} />
    </span>
    """
  end

  attr :result, :map, required: true

  defp search_result_label(assigns) do
    ~H"""
    <.favicon domain={@result.domain} />
    <span class="shrink-0 text-base-content/40">{@result.domain}</span>
    <span class="truncate">{@result.title}</span>
    """
  end

  attr :domain, :string, default: nil

  # Google's favicon service, so the browser discloses each researched domain to Google.
  # Accepted for an internal admin tool; the alternative is proxying icons ourselves.
  defp favicon(assigns) do
    ~H"""
    <img
      :if={@domain not in [nil, ""]}
      src={"https://www.google.com/s2/favicons?domain=#{URI.encode_www_form(@domain)}&sz=32"}
      alt=""
      class="size-3.5 shrink-0 rounded-sm"
    />
    <.icon
      :if={@domain in [nil, ""]}
      name="hero-globe-alt"
      class="size-3.5 shrink-0 text-base-content/60"
    />
    """
  end

  attr :call, :map, required: true

  defp mcp_call_row(assigns) do
    assigns =
      assign(assigns,
        args: arg_summary(assigns.call),
        status: call_status(assigns.call),
        has_output: !!assigns.call[:summary]
      )

    ~H"""
    <details class="text-xs">
      <summary class="flex cursor-pointer list-none items-center gap-2 text-left">
        <span class="truncate font-mono text-base-content/80">
          {@call.tool}{if @args != "", do: "(#{@args})", else: "()"}
        </span>
        <.status_icon
          status={@status}
          size="size-3"
          class="ml-auto"
          interrupted_title="Interrupted — did not return"
        />
      </summary>
      <pre
        :if={@has_output}
        class="mt-1 max-h-32 overflow-auto whitespace-pre-wrap rounded bg-base-300/40 p-2 text-[11px] text-base-content/60"
      >{@call.summary}</pre>
    </details>
    """
  end

  attr :status, :atom, required: true, values: [:running, :ok, :error, :interrupted]
  attr :size, :string, default: "size-4", doc: "size utility for the non-spinner glyphs"
  attr :class, :string, default: nil, doc: "positioning/colour extras (e.g. \"ml-auto\")"
  attr :interrupted_title, :string, default: "Interrupted — some calls did not return"

  # The one glyph for every tool outcome: spinner running, check ok, cross error,
  # neutral minus interrupted. Statuses come from `group_status/1` / `call_status/1`.
  defp status_icon(%{status: :running} = assigns) do
    ~H"""
    <span class={["loading loading-spinner loading-xs", @class]}></span>
    """
  end

  defp status_icon(%{status: :ok} = assigns) do
    ~H"""
    <.icon name="hero-check-circle" class={"#{@size} text-success #{@class}"} />
    """
  end

  defp status_icon(%{status: :error} = assigns) do
    ~H"""
    <.icon name="hero-x-circle" class={"#{@size} text-error #{@class}"} />
    """
  end

  defp status_icon(%{status: :interrupted} = assigns) do
    ~H"""
    <span class={@class} title={@interrupted_title}>
      <.icon name="hero-minus-circle" class={"#{@size} text-base-content/40"} />
    </span>
    """
  end

  # :running while anything is in flight, :interrupted when a call never returned, else
  # :ok. Individual failures stay on their own row - a run tolerates a failed call, but a
  # group cut short must not claim success.
  defp group_status(items) do
    cond do
      Timeline.tools_running?(items) ->
        :running

      Enum.any?(items, &(&1.kind in [:mcp, :fetch] and is_nil(Map.get(&1, :ok)))) ->
        :interrupted

      true ->
        :ok
    end
  end

  # `ok: nil` on a finished call means the run ended before the result arrived —
  # neither success nor failure.
  defp call_status(call) do
    cond do
      Map.get(call, :done) != true -> :running
      call[:ok] == true -> :ok
      call[:ok] == false -> :error
      true -> :interrupted
    end
  end

  attr :id, :integer, required: true
  attr :report, :string, required: true

  defp report_card(assigns) do
    ~H"""
    <div class="overflow-hidden rounded-xl border border-base-300 bg-base-100 shadow-sm">
      <div class="flex items-center gap-2 border-b border-base-300 bg-base-200/40 px-4 py-2.5">
        <.icon name="hero-document-text" class="size-4 text-primary" />
        <span class="text-xs font-semibold uppercase tracking-wide text-base-content/60">
          Research report
        </span>
        <button
          type="button"
          id={"copy-report-#{@id}"}
          phx-hook="Copy"
          data-copy={@report}
          class="ml-auto inline-flex items-center gap-1.5 rounded-lg px-2 py-1 text-xs text-base-content/50 transition hover:bg-base-200 hover:text-base-content"
        >
          <.icon name="hero-clipboard-document" class="size-4 [.copied_&]:hidden" />
          <.icon name="hero-check" class="hidden size-4 text-success [.copied_&]:inline-block" />
          <span class="[.copied_&]:hidden">Copy</span>
          <span class="hidden [.copied_&]:inline">Copied</span>
        </button>
      </div>
      <div class="space-y-4 px-5 py-4">
        <%= for seg <- ReportMarkdown.split_charts(ReportMarkdown.reflow_sources(@report)) do %>
          <%= case seg do %>
            <% {:md, text} -> %>
              <div class="prose prose-sm max-w-none">{markdown(text)}</div>
            <% {:chart, spec} -> %>
              {ChartRenderer.render(spec)}
          <% end %>
        <% end %>
      </div>
    </div>
    """
  end

  # -- view helpers ------------------------------------------------------------

  # Settle an in-flight item (done, outcome unknown) so a terminal turn shows no
  # spinner. `ok` stays nil, so the row renders "interrupted", not a false check.
  defp settle_item(%{kind: kind, done: true} = item) when kind in [:mcp, :fetch], do: item

  defp settle_item(%{kind: kind} = item) when kind in [:mcp, :fetch],
    do: Map.put(item, :done, true)

  defp settle_item(%{kind: :search} = item) do
    if is_nil(Map.get(item, :count)),
      do: Map.put(item, :count, length(item[:results] || [])),
      else: item
  end

  # A summary that never landed: the turn is over, so it is not going to.
  defp settle_item(%{kind: :compaction, state: "compacting"} = item),
    do: %{item | state: "interrupted"}

  defp settle_item(item), do: item

  attr :text, :string, required: true

  # A weak sub-agent sometimes pastes a whole series into one field ("2026-06-05,-0.2025;
  # 2026-06-06,…" for 70 days) instead of summarizing it. Rendered raw that is a wall of
  # numbers with nothing to collapse, so the run of points is folded into one line the
  # reader can expand. Prose around the run is kept as it is.
  defp series_text(assigns) do
    assigns = assign(assigns, :parts, Timeline.split_series_runs(assigns.text))

    ~H"""
    <span :for={part <- @parts}>
      <span :if={is_binary(part)}>{part}</span>
      <details
        :if={is_map(part)}
        class="my-1 inline-block w-full rounded border border-base-300 bg-base-100/60"
      >
        <summary class="cursor-pointer list-none px-2 py-1 text-xs text-base-content/60 hover:text-base-content">
          <.icon name="hero-table-cells" class="mr-1 inline size-3.5 text-base-content/40" />{part.label}
        </summary>
        <pre class="max-h-48 overflow-auto whitespace-pre-wrap break-all px-2 py-1 font-mono text-[11px] leading-snug">{part.text}</pre>
      </details>
    </span>
    """
  end

  # Cheap models drift the keys (finding/observation, evidence/data) — try each.
  defp finding_field(row, keys) when is_map(row) do
    Enum.find_value(keys, "", fn k ->
      case row[k] do
        v when is_binary(v) and v != "" -> v
        _ -> nil
      end
    end)
  end

  defp finding_field(_, _), do: ""

  # Series come straight off the wire, so the keys are strings — see the "Not the only
  # chart path" note in `SanbaseWeb.DeepResearch.ChartRenderer`.
  defp chart_caption(chart) do
    base = [chart[:slug], chart[:range]] |> Enum.reject(&is_nil/1) |> Enum.join(" · ")

    labels =
      (chart.series || [])
      |> Enum.map(&(&1["label"] || &1["name"]))
      |> Enum.reject(&(&1 in [nil, ""]))
      |> Enum.uniq()

    case {base, labels} do
      {"", []} -> "Chart"
      {b, []} -> b
      {"", ls} -> Enum.join(ls, " vs ")
      {b, ls} -> "#{b} — #{Enum.join(ls, " vs ")}"
    end
  end

  # The report and clarification cards render separately, so narration repeating them
  # is noise.
  defp visible_items(timeline, report, clarification) do
    Enum.reject(timeline, fn item ->
      # Text may be nil on a turn decoded from an older row — as in
      # Timeline.direct_answer?/1.
      text = (item.kind == :thinking && item.text) || ""

      item.kind == :thinking and
        ((is_binary(report) and String.trim(text) == String.trim(report)) or
           (is_list(clarification) and clarification != [] and
              Enum.all?(clarification, &String.contains?(text, &1))))
    end)
  end

  defp tool_summary(items) do
    n_search = Enum.count(items, &(&1.kind == :search))
    n_mcp = Enum.count(items, &(&1.kind == :mcp))
    n_fetch = Enum.count(items, &(&1.kind == :fetch))

    parts =
      []
      |> append_if(n_search > 0, "#{n_search} web #{pluralize(n_search, "search", "searches")}")
      |> append_if(n_mcp > 0, "#{n_mcp} data #{pluralize(n_mcp, "call", "calls")}")
      |> append_if(n_fetch > 0, "#{n_fetch} #{pluralize(n_fetch, "page", "pages")} read")

    case parts do
      [] -> if Enum.any?(items, &(&1.kind == :status)), do: "status", else: "reasoning"
      parts -> Enum.join(parts, " · ")
    end
  end

  defp append_if(list, true, value), do: list ++ [value]
  defp append_if(list, false, _value), do: list

  defp script_lines(%{code: code}) when is_binary(code) do
    code |> String.trim_trailing("\n") |> String.split("\n") |> length()
  end

  defp script_lines(_), do: 0

  defp pluralize(1, singular, _plural), do: singular
  defp pluralize(_n, _singular, plural), do: plural

  defp arg_summary(%{args: args}) when is_map(args) do
    args
    |> Enum.reject(fn {_k, v} -> v in [nil, "None", ""] end)
    |> Enum.map_join(", ", fn {k, v} -> "#{k}=#{stringify(v)}" end)
    |> String.slice(0, 140)
  end

  defp arg_summary(_), do: ""

  # Values are where content lives (a file body, a code snippet, a brief); the finished
  # row shows the shape of the call, never the payload — the live draft's rule too.
  @arg_value_max_chars 60

  defp stringify(v) do
    s = if is_binary(v), do: v, else: inspect(v)
    n = String.length(s)
    if n > @arg_value_max_chars, do: "[#{n} chars]", else: s
  end

  defp safe_http_url(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{scheme: scheme} when scheme in ["http", "https"] -> url
      _ -> nil
    end
  end

  defp safe_http_url(_), do: nil

  # A finished turn carries `finished_at`, so `now_ms: nil` keeps its assigns stable
  # across ticks.
  defp elapsed_seconds(turn, now_ms) do
    end_ms = turn.finished_at || now_ms || turn.started_at
    max(0, div(end_ms - turn.started_at, 1000))
  end

  # Once the turn has settled, the agent's own run clock (its usage ledger) wins: it is
  # the number the agent quotes in its end status ("Run time 4m 12s."), so the footer
  # and the error box agree. Before that, and for a run that died before reporting
  # usage, the wall clock stands in.
  defp elapsed_seconds(turn, now_ms, %{elapsed_s: s}) when is_number(s) do
    if turn.finished_at, do: max(0, round(s)), else: elapsed_seconds(turn, now_ms)
  end

  defp elapsed_seconds(turn, now_ms, _usage), do: elapsed_seconds(turn, now_ms)

  defp format_duration(seconds) when seconds < 60, do: "#{seconds}s"

  defp format_duration(seconds) do
    minutes = div(seconds, 60)
    rest = rem(seconds, 60)
    "#{minutes}m #{String.pad_leading(Integer.to_string(rest), 2, "0")}s"
  end

  # The markdown arrives over the wire, so sanitize before injecting it raw - Earmark
  # converts, it does not sanitize. `as_html/1`, not the bang: streaming renders parse
  # PARTIAL markdown (an open ``` fence) and `as_html!/1` prints every parse error to
  # stderr on each re-render. Both return best-effort HTML.
  defp markdown(text) when is_binary(text) do
    {_status, html, _messages} = Earmark.as_html(text)

    html
    |> HtmlSanitizeEx.markdown_html()
    |> Phoenix.HTML.raw()
  end

  defp markdown(_), do: ""

  defp phase_label(:queued), do: "Queued on the agent server"
  defp phase_label(:planning), do: "Planning research"
  defp phase_label(:researching), do: "Researching"
  defp phase_label(:writing), do: "Writing report"
  defp phase_label(:paused), do: "Paused"
  defp phase_label(_), do: "Working"
end
