defmodule SanbaseWeb.DeepResearchLive do
  @moduledoc """
  Deep research agent UI, implemented as a Phoenix LiveView.

  The LiveView connects directly to a LangGraph deep research agent over SSE
  (`Sanbase.DeepResearch.Client`), streams the typed event protocol, reduces it
  into per-turn state (`Sanbase.DeepResearch.Timeline`) and renders the live
  research view: clarification cards, web-search globe rows, MCP call rows,
  skill chips, streamed thinking, and the final cited markdown report.

  The streaming run is driven by `start_async/3` (like `AskLive`) so the LiveView
  process keeps serving websocket heartbeats during long runs and the task is
  auto-cancelled if the LiveView goes down.
  """
  use SanbaseWeb, :live_view

  alias Sanbase.DeepResearch.{Client, EventParser, Timeline}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       turns: [],
       thread_id: nil,
       run_id: nil,
       running: false,
       query: "",
       mcp_warning: nil,
       next_id: 1,
       now_ms: now_ms()
     )}
  end

  # -- events ------------------------------------------------------------------

  @impl true
  def handle_event("update_query", %{"query" => query}, socket) do
    {:noreply, assign(socket, :query, query)}
  end

  def handle_event("use_example", %{"q" => query}, socket) do
    {:noreply, assign(socket, :query, query)}
  end

  def handle_event("submit", %{"query" => query}, socket) do
    text = String.trim(query)

    if text == "" or socket.assigns.running do
      {:noreply, socket}
    else
      {:noreply, start_research(socket, text)}
    end
  end

  def handle_event("cancel", _params, socket) do
    cancel_run_async(socket.assigns.thread_id, socket.assigns.run_id)

    socket =
      socket
      |> cancel_async(:research)
      |> update_last_turn(fn turn ->
        %{turn | phase: :cancelled, finished_at: turn.finished_at || now_ms()}
      end)
      |> assign(running: false)

    {:noreply, socket}
  end

  defp start_research(socket, text) do
    id = socket.assigns.next_id
    now = now_ms()
    turn = Timeline.new_turn(text, id, now)
    lv = self()
    thread_id = socket.assigns.thread_id

    # The run streams off the socket via start_async/3 (like AskLive) so the
    # LiveView process keeps serving heartbeats; incremental events arrive as
    # {:dra_event, _} messages, the terminal status via handle_async/3.
    socket
    |> assign(
      turns: socket.assigns.turns ++ [turn],
      running: true,
      query: "",
      run_id: nil,
      next_id: id + 1,
      now_ms: now
    )
    |> schedule_tick()
    |> start_async(:research, fn -> run_stream(thread_id, text, lv) end)
  end

  # Runs in the async task: create the thread on the first turn, then stream.
  # Returns the terminal status (handled by handle_async/3).
  defp run_stream(nil, text, lv) do
    case Client.create_thread() do
      {:ok, thread_id} ->
        send(lv, {:dra_thread, thread_id})
        Client.stream_run(thread_id, text, lv)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp run_stream(thread_id, text, lv) when is_binary(thread_id) do
    Client.stream_run(thread_id, text, lv)
  end

  # -- streamed messages -------------------------------------------------------

  @impl true
  def handle_info({:dra_thread, thread_id}, socket) do
    socket =
      if is_nil(socket.assigns.thread_id),
        do: assign(socket, :thread_id, thread_id),
        else: socket

    {:noreply, socket}
  end

  def handle_info({:dra_event, result}, socket) do
    socket =
      socket
      |> apply_socket_level(result)
      |> update_last_turn(&Timeline.apply_result(&1, result))

    {:noreply, socket}
  end

  # Poll-state fallback: only fill a missing report — never overwrite the turn's
  # own report, and never revive a failed/cancelled/awaiting turn.
  def handle_info({:dra_poll, result}, socket) do
    socket =
      update_last_turn(socket, fn turn ->
        cond do
          turn.phase in [:failed, :cancelled, :awaiting_user] -> turn
          turn.report -> turn
          is_binary(result[:report]) -> %{turn | report: result[:report], phase: :completed}
          true -> turn
        end
      end)

    {:noreply, socket}
  end

  def handle_info(:tick, socket) do
    if socket.assigns.running do
      {:noreply, socket |> assign(:now_ms, now_ms()) |> schedule_tick()}
    else
      {:noreply, socket}
    end
  end

  # Terminal status of the streaming run (start_async/3). The async task is
  # automatically cancelled if the LiveView process goes down.
  @impl true
  def handle_async(:research, {:ok, :ok}, socket) do
    {:noreply, finalize_run(socket)}
  end

  def handle_async(:research, {:ok, {:error, reason}}, socket) do
    {:noreply, fail_run(socket, reason)}
  end

  def handle_async(:research, {:exit, reason}, socket) do
    {:noreply, fail_run(socket, "Research stopped unexpectedly (#{inspect(reason)})")}
  end

  # -- state helpers -----------------------------------------------------------

  defp finalize_run(socket) do
    if socket.assigns.running do
      socket = socket |> update_last_turn(&finalize_turn/1) |> assign(running: false)
      maybe_poll_state(socket)
      socket
    else
      socket
    end
  end

  defp fail_run(socket, reason) do
    if socket.assigns.running do
      socket
      |> update_last_turn(fn turn ->
        %{
          turn
          | phase: Timeline.merge_phase(turn.phase, :failed),
            error: turn.error || reason,
            finished_at: turn.finished_at || now_ms()
        }
      end)
      |> assign(running: false)
    else
      socket
    end
  end

  defp apply_socket_level(socket, result) do
    socket =
      case result do
        %{run_id: id} -> assign(socket, :run_id, id)
        _ -> socket
      end

    case result do
      %{meta: %{mcp_warning: warning}} -> assign(socket, :mcp_warning, warning)
      _ -> socket
    end
  end

  defp finalize_turn(turn) do
    phase =
      if turn.phase in [:failed, :cancelled, :awaiting_user], do: turn.phase, else: :completed

    %{turn | phase: phase, finished_at: turn.finished_at || now_ms()}
  end

  defp update_last_turn(socket, fun) do
    case socket.assigns.turns do
      [] ->
        socket

      turns ->
        {init, [last]} = Enum.split(turns, -1)
        assign(socket, :turns, init ++ [fun.(last)])
    end
  end

  defp maybe_poll_state(socket) do
    turn = List.last(socket.assigns.turns)
    thread_id = socket.assigns.thread_id

    if thread_id && turn && is_nil(turn.report) && turn.phase == :completed do
      poll_state_async(thread_id, self())
    end

    :ok
  end

  defp poll_state_async(thread_id, lv) do
    Task.Supervisor.start_child(Sanbase.TaskSupervisor, fn ->
      case Client.get_state(thread_id) do
        {:ok, state} -> send(lv, {:dra_poll, EventParser.parse_thread_state(state)})
        _ -> :ok
      end
    end)
  end

  defp cancel_run_async(thread_id, run_id) when is_binary(thread_id) and is_binary(run_id) do
    Task.Supervisor.start_child(Sanbase.TaskSupervisor, fn ->
      Client.cancel_run(thread_id, run_id)
    end)
  end

  defp cancel_run_async(_thread_id, _run_id), do: :ok

  defp schedule_tick(socket) do
    Process.send_after(self(), :tick, 1000)
    socket
  end

  defp now_ms(), do: System.system_time(:millisecond)

  # -- render ------------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto flex h-[calc(100vh-10rem)] w-full max-w-5xl flex-col px-4">
      <div
        :if={@turns == []}
        class="flex min-h-0 flex-1 flex-col items-center justify-center text-center"
      >
        <div class="mb-6 flex size-12 items-center justify-center rounded-2xl bg-base-200 text-base-content/70">
          <.icon name="hero-beaker" class="size-6" />
        </div>
        <h1 class="text-3xl font-semibold tracking-tight sm:text-[2rem]">
          What do you want to research?
        </h1>
        <p class="mt-3 max-w-lg text-base-content/55">
          A crypto research agent. I'll plan, search the web and Santiment data, and write a cited,
          sourced report — asking a clarifying question or two first if the request is broad.
        </p>
        <div class="mt-6 flex flex-wrap justify-center gap-2">
          <button
            :for={{label, prompt} <- example_prompts()}
            type="button"
            phx-click="use_example"
            phx-value-q={prompt}
            class="rounded-full border border-base-300 bg-base-100 px-3.5 py-1.5 text-sm text-base-content/70 transition hover:border-base-content/20 hover:bg-base-200 hover:text-base-content"
          >
            {label}
          </button>
        </div>
      </div>

      <div :if={@turns != []} class="min-h-0 flex-1 space-y-8 overflow-y-auto py-4">
        <.turn_view
          :for={{turn, index} <- Enum.with_index(@turns)}
          turn={turn}
          running={index == length(@turns) - 1 and @running}
          now_ms={@now_ms}
        />
      </div>

      <div class="shrink-0 pt-2">
        <p :if={@mcp_warning} class="mb-2 px-1 text-xs text-warning" role="status">
          {@mcp_warning}
        </p>
        <.composer
          query={@query}
          running={@running}
          placeholder={
            if @turns == [],
              do: "Ask anything about crypto markets, assets, on-chain & social metrics…",
              else: "Reply, or ask a follow-up…"
          }
        />
        <p class="mt-2 text-center text-[11px] text-base-content/40">
          Deep research runs can take a few minutes · responses include cited sources
        </p>
      </div>
    </div>
    """
  end

  attr :query, :string, required: true
  attr :running, :boolean, required: true
  attr :placeholder, :string, required: true

  defp composer(assigns) do
    ~H"""
    <form phx-submit="submit" phx-change="update_query">
      <div class="flex items-end gap-2 rounded-[1.75rem] border border-base-300 bg-base-100 py-1.5 pl-4 pr-2 shadow-sm transition focus-within:border-base-content/25 focus-within:shadow-md">
        <textarea
          name="query"
          rows="1"
          phx-debounce="150"
          disabled={@running}
          placeholder={@placeholder}
          class="max-h-44 min-h-[2.75rem] flex-1 resize-none bg-transparent py-2.5 text-[15px] leading-relaxed placeholder:text-base-content/40 focus:outline-none disabled:opacity-60"
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

  attr :turn, :map, required: true
  attr :running, :boolean, required: true
  attr :now_ms, :integer, required: true

  defp turn_view(assigns) do
    ~H"""
    <div class="space-y-4">
      <div class="flex justify-end">
        <div class="max-w-[80%] break-words rounded-2xl rounded-br-sm bg-primary px-4 py-2.5 text-sm leading-relaxed text-primary-content">
          {@turn.question}
        </div>
      </div>

      <.research_timeline turn={@turn} running={@running} now_ms={@now_ms} />

      <.clarification_card
        :if={@turn.clarification && @turn.clarification != []}
        questions={@turn.clarification}
      />

      <div
        :if={@turn.error}
        class="flex items-start gap-2 rounded-xl border border-error/30 bg-error/5 px-4 py-3 text-sm text-error"
        role="alert"
      >
        <.icon name="hero-exclamation-triangle" class="mt-0.5 size-4 shrink-0" />
        <span>{@turn.error}</span>
      </div>
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
  attr :now_ms, :integer, required: true

  defp research_timeline(assigns) do
    turn = assigns.turn
    proc_items = visible_items(turn.timeline, turn.report, turn.clarification)
    blocks = Timeline.segment(proc_items)
    has_research = Enum.any?(blocks, &match?({:tools, _, _}, &1)) or not is_nil(turn.report)

    assigns =
      assign(assigns,
        blocks: blocks,
        has_research: has_research,
        empty?: proc_items == [] and is_nil(turn.report)
      )

    ~H"""
    <div :if={not (@empty? and not @running)} class="space-y-3">
      <%= for {block, index} <- Enum.with_index(@blocks) do %>
        <.timeline_block block={block} index={index} />
      <% end %>

      <.report_card :if={@turn.report} id={@turn.id} report={@turn.report} />

      <div
        :if={@running}
        class="flex items-center gap-2 text-xs font-medium text-base-content/60"
      >
        <span class="loading loading-spinner loading-xs text-primary"></span>
        {phase_label(@turn.phase)} · {format_duration(elapsed_seconds(@turn, @now_ms))}
      </div>
      <div
        :if={((not @running and @turn.started_at) && @has_research) and @turn.phase == :completed}
        class="flex items-center gap-1.5 text-xs text-base-content/50"
      >
        <.icon name="hero-check-circle" class="size-3.5 text-success" />
        Researched in {format_duration(elapsed_seconds(@turn, @now_ms))}
      </div>
      <div
        :if={@turn.phase == :cancelled and @has_research}
        class="flex items-center gap-1.5 text-xs text-base-content/40"
      >
        <.icon name="hero-no-symbol" class="size-3.5" />
        Stopped after {format_duration(elapsed_seconds(@turn, @now_ms))}
      </div>
    </div>
    """
  end

  attr :block, :any, required: true
  attr :index, :integer, required: true

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

  defp timeline_block(%{block: {:tools, items, running}} = assigns) do
    assigns = assign(assigns, items: items, running: running, summary: tool_summary(items))

    ~H"""
    <details class="group rounded-xl border border-base-300 bg-base-200/30" open={@running}>
      <summary class="flex cursor-pointer list-none items-center gap-2 rounded-xl px-3.5 py-2.5 text-xs font-medium text-base-content/60 hover:text-base-content">
        <span :if={@running} class="loading loading-spinner loading-xs text-primary"></span>
        <.icon :if={not @running} name="hero-check-circle" class="size-4 text-success" />
        <span class="text-base-content/80">Research</span>
        <span class="text-base-content/50">· {@summary}</span>
        <.icon
          name="hero-chevron-down"
          class="ml-auto size-4 text-base-content/40 transition-transform group-open:rotate-0 -rotate-90"
        />
      </summary>
      <div class="space-y-3 border-t border-base-300 px-3.5 py-3">
        <%= for {item, i} <- Enum.with_index(Timeline.coalesce(@items)) do %>
          <.tool_item item={item} index={i} />
        <% end %>
      </div>
    </details>
    """
  end

  attr :item, :any, required: true
  attr :index, :integer, required: true

  defp tool_item(%{item: {:mcp_group, items}} = assigns) do
    assigns = assign(assigns, items: items, running: Timeline.tools_running?(items))

    ~H"""
    <details class="group">
      <summary class="flex cursor-pointer list-none items-center gap-2 text-sm text-base-content/80 hover:text-base-content">
        <.icon name="hero-circle-stack" class="size-4 text-indigo-500" />
        <span class="font-medium">Data tools</span>
        <span class="text-xs text-base-content/60">
          · {length(@items)} {pluralize(length(@items), "call", "calls")}
        </span>
        <span :if={@running} class="loading loading-spinner loading-xs ml-auto"></span>
        <.icon :if={not @running} name="hero-check-circle" class="ml-auto size-3.5 text-success" />
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
        <span :if={is_nil(Map.get(@item, :count))} class="loading loading-spinner loading-xs ml-auto">
        </span>
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

  defp tool_item(%{item: %{kind: :status}} = assigns) do
    ~H"""
    <p class={[
      "text-xs",
      if(@item.state == "mcp_error", do: "text-error", else: "text-base-content/60")
    ]}>
      {if @item.state == "mcp_error",
        do: "MCP error: #{@item[:detail] || "connection failed"}",
        else: "Connected to data tools"}
    </p>
    """
  end

  defp tool_item(assigns), do: ~H""

  attr :result, :map, required: true

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
      <.favicon domain={@result.domain} />
      <span class="shrink-0 text-base-content/40">{@result.domain}</span>
      <span class="truncate">{@result.title}</span>
    </.link>
    <span
      :if={!@href}
      title={@result.title}
      class="flex items-center gap-1.5 overflow-hidden text-xs text-base-content/60"
    >
      <.favicon domain={@result.domain} />
      <span class="shrink-0 text-base-content/40">{@result.domain}</span>
      <span class="truncate">{@result.title}</span>
    </span>
    """
  end

  attr :domain, :string, default: nil

  defp favicon(assigns) do
    ~H"""
    <img
      :if={@domain not in [nil, ""]}
      src={"https://www.google.com/s2/favicons?domain=#{@domain}&sz=32"}
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
      assign(assigns, args: arg_summary(assigns.call), has_output: !!assigns.call[:summary])

    ~H"""
    <details class="text-xs">
      <summary class="flex cursor-pointer list-none items-center gap-2 text-left">
        <span class="truncate font-mono text-base-content/80">
          {@call.tool}{if @args != "", do: "(#{@args})", else: "()"}
        </span>
        <span :if={Map.get(@call, :done) != true} class="loading loading-spinner loading-xs ml-auto">
        </span>
        <.icon
          :if={Map.get(@call, :done) == true}
          name="hero-check-circle"
          class={"ml-auto size-3 #{if @call[:ok] == false, do: "text-error", else: "text-success"}"}
        />
      </summary>
      <pre
        :if={@has_output}
        class="mt-1 max-h-32 overflow-auto whitespace-pre-wrap rounded bg-base-300/40 p-2 text-[11px] text-base-content/60"
      >{@call.summary}</pre>
    </details>
    """
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
      <div class="px-5 py-4">
        <div class="prose prose-sm max-w-none">
          {markdown(Timeline.reflow_sources(@report))}
        </div>
      </div>
    </div>
    """
  end

  # -- view helpers ------------------------------------------------------------

  # Drop narration that duplicates the report or clarification card — those are
  # rendered separately, so showing the same text in the feed is just noise.
  defp visible_items(timeline, report, clarification) do
    Enum.reject(timeline, fn item ->
      item.kind == :thinking and
        ((is_binary(report) and String.trim(item.text) == String.trim(report)) or
           (is_list(clarification) and clarification != [] and
              Enum.all?(clarification, &String.contains?(item.text, &1))))
    end)
  end

  defp tool_summary(items) do
    n_search = Enum.count(items, &(&1.kind == :search))
    n_mcp = Enum.count(items, &(&1.kind == :mcp))

    parts =
      []
      |> append_if(n_search > 0, "#{n_search} web #{pluralize(n_search, "search", "searches")}")
      |> append_if(n_mcp > 0, "#{n_mcp} data #{pluralize(n_mcp, "call", "calls")}")

    case parts do
      [] -> "reasoning"
      parts -> Enum.join(parts, " · ")
    end
  end

  defp append_if(list, true, value), do: list ++ [value]
  defp append_if(list, false, _value), do: list

  defp pluralize(1, singular, _plural), do: singular
  defp pluralize(_n, _singular, plural), do: plural

  defp arg_summary(%{args: args}) when is_map(args) do
    args
    |> Enum.reject(fn {_k, v} -> v in [nil, "None", ""] end)
    |> Enum.map_join(", ", fn {k, v} -> "#{k}=#{stringify(v)}" end)
    |> String.slice(0, 140)
  end

  defp arg_summary(_), do: ""

  defp stringify(v) when is_binary(v), do: v
  defp stringify(v), do: inspect(v)

  defp safe_http_url(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{scheme: scheme} when scheme in ["http", "https"] -> url
      _ -> nil
    end
  end

  defp safe_http_url(_), do: nil

  defp elapsed_seconds(turn, now_ms) do
    end_ms = turn.finished_at || now_ms
    max(0, div(end_ms - turn.started_at, 1000))
  end

  defp format_duration(seconds) when seconds < 60, do: "#{seconds}s"

  defp format_duration(seconds) do
    minutes = div(seconds, 60)
    rest = rem(seconds, 60)
    "#{minutes}m #{String.pad_leading(Integer.to_string(rest), 2, "0")}s"
  end

  defp markdown(text) when is_binary(text) do
    Phoenix.HTML.raw(Earmark.as_html!(text))
  end

  defp markdown(_), do: ""

  defp phase_label(:planning), do: "Planning research"
  defp phase_label(:researching), do: "Researching"
  defp phase_label(:writing), do: "Writing report"
  defp phase_label(_), do: "Working"

  defp example_prompts() do
    [
      {"Compare ETH vs SOL on-chain",
       "Compare ETH and SOL on-chain activity and fees over the last quarter"},
      {"What's moving Bitcoin?",
       "What's driving Bitcoin's recent price action — on-chain and social signals?"},
      {"Solana DeFi health",
       "Assess the current state of the Solana DeFi ecosystem and its key risks"}
    ]
  end
end
