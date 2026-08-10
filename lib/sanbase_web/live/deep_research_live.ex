defmodule SanbaseWeb.DeepResearchLive do
  @moduledoc """
  Deep research agent UI, implemented as a Phoenix LiveView.

  The LiveView connects directly to a LangGraph deep research agent over SSE
  (`Sanbase.DeepResearch.Client`), streams the typed event protocol, reduces it
  into per-turn state (`Sanbase.DeepResearch.Timeline`) and renders it through
  `SanbaseWeb.DeepResearch.Components`. This module owns only the socket state
  and the async plumbing; all markup lives in the components module.

  The streaming run is driven by `start_async/3` (like `AskLive`) so the LiveView
  process keeps serving websocket heartbeats during long runs and the task is
  auto-cancelled if the LiveView goes down.

  ## Turn state

  The transcript is split in two assigns on purpose:

    * `:turns` — finished turns, oldest first. Never touched while a run streams,
      so LiveView re-renders none of them per event or per one-second tick.
    * `:current_turn` — the turn being streamed into (or the most recent finished
      one, until the next question pushes it onto `:turns`).

  Every message from the async work carries the turn id as an opaque `ref`.
  Anything whose ref is not the current turn's is dropped: a slow state poll or a
  late event from a cancelled run must never land on a turn that started after it.
  """
  use SanbaseWeb, :live_view

  require Logger

  import SanbaseWeb.DeepResearch.Components, only: [composer: 1, turn_view: 1, sidebar: 1]

  alias Sanbase.DeepResearch.{Client, Config, EventParser, Sessions, Timeline}

  @no_report_error "The research run finished without producing a report — the agent stopped " <>
                     "before delivering one (it may have hit a tool/iteration budget or been " <>
                     "unable to complete the task). Try rephrasing or narrowing your question."

  @impl true
  def mount(_params, _session, socket) do
    catalog = Config.mcp_catalog()

    socket =
      socket
      |> assign(
        mcp_catalog: catalog,
        # All configured MCP servers are enabled (connected) by default.
        mcp_enabled: MapSet.new(Enum.map(catalog, & &1.key)),
        # Model price tier (the only model knob the agent exposes per run). The
        # dropdown is feature-flagged; when off, every run uses the deploy default.
        tiering_dropdown_enabled: Config.tiering_dropdown_enabled?(),
        model_tiers: Config.model_tiers(),
        model_tier: Config.default_model_tier()
      )
      |> reset_conversation()
      |> refresh_sessions()

    {:ok, socket}
  end

  # Fires on mount and on every push_patch. Navigating away from a streaming
  # run cancels it first — a reused LiveView process must not keep an orphaned
  # run streaming (and billing) into state the user just left.
  @impl true
  def handle_params(params, _uri, socket) do
    if params["id"] && params["id"] == socket.assigns.session_id do
      # Our own patch announcing the session the process already holds — the
      # permalink issued on first submit, or a sidebar click on the open
      # session. The state (possibly a streaming run) is current; reloading
      # would destroy it.
      {:noreply, socket}
    else
      socket = if socket.assigns.running, do: cancel_current_run(socket), else: socket

      case socket.assigns.live_action do
        :show -> open_session(socket, params["id"])
        _ -> {:noreply, reset_conversation(socket)}
      end
    end
  end

  # Reopen a past session: the owner can keep chatting with it. Restoring the
  # session's thread_id resumes the same LangGraph thread, so the agent keeps
  # its context; new turns append after the last persisted position.
  defp open_session(socket, session_id) do
    user = socket.assigns[:current_user]

    case user && Sessions.get_session_for_user(session_id, user.id) do
      {:ok, %{session: session, turns: turns}} ->
        {:noreply,
         socket
         |> reset_conversation()
         |> assign(
           turns: turns,
           session_id: session.id,
           thread_id: session.thread_id,
           next_id: next_position(turns)
         )}

      # :forbidden collapses into "not found" so a session id never leaks
      # whether it exists. push_navigate (not patch): this branch can run
      # during mount, where patching is not allowed.
      _ ->
        {:noreply,
         socket
         |> put_flash(:error, "Research session not found.")
         |> push_navigate(to: ~p"/admin/deep_research")}
    end
  end

  defp next_position([]), do: 1
  defp next_position(turns), do: List.last(turns).id + 1

  defp reset_conversation(socket) do
    assign(socket,
      turns: [],
      current_turn: nil,
      thread_id: nil,
      run_id: nil,
      running: false,
      query: "",
      mcp_warning: nil,
      next_id: 1,
      session_id: nil,
      now_ms: now_ms()
    )
  end

  # -- events ------------------------------------------------------------------

  @impl true
  def handle_event("update_query", %{"query" => query}, socket) do
    {:noreply, assign(socket, :query, query)}
  end

  def handle_event("use_example", %{"q" => query}, socket) do
    {:noreply, assign(socket, :query, query)}
  end

  def handle_event("select_tier", %{"model_tier" => tier}, socket) do
    # Whitelist against the catalog (and the feature flag — a crafted event must
    # not change the tier when the dropdown is off). Anything else keeps current.
    valid? =
      socket.assigns.tiering_dropdown_enabled and
        Enum.any?(socket.assigns.model_tiers, fn {value, _, _} -> value == tier end)

    {:noreply, if(valid?, do: assign(socket, :model_tier, tier), else: socket)}
  end

  def handle_event("toggle_mcp", %{"key" => key}, socket) do
    enabled = socket.assigns.mcp_enabled

    enabled =
      if MapSet.member?(enabled, key),
        do: MapSet.delete(enabled, key),
        else: MapSet.put(enabled, key)

    {:noreply, assign(socket, :mcp_enabled, enabled)}
  end

  def handle_event("submit", %{"query" => query}, socket) do
    text = String.trim(query)

    if text == "" or socket.assigns.running do
      {:noreply, socket}
    else
      {:noreply, start_research(socket, text)}
    end
  end

  # A cancel with no run in flight (double click, crafted event) must not touch
  # the finished turn or fire a cancel request at the agent server.
  def handle_event("cancel", _params, %{assigns: %{running: false}} = socket),
    do: {:noreply, socket}

  def handle_event("cancel", _params, socket) do
    {:noreply, cancel_current_run(socket)}
  end

  # -- sidebar events ------------------------------------------------------------

  def handle_event("new_session", _params, socket) do
    {:noreply, push_patch(socket, to: ~p"/admin/deep_research")}
  end

  def handle_event("open_session", %{"id" => id}, socket) do
    {:noreply, push_patch(socket, to: ~p"/admin/deep_research/#{id}")}
  end

  def handle_event("toggle_public", %{"id" => id}, socket) do
    with %{} = user <- socket.assigns[:current_user] do
      Sessions.toggle_public(id, user.id)
    end

    {:noreply, refresh_sessions(socket)}
  end

  def handle_event("delete_session", %{"id" => id}, socket) do
    with %{} = user <- socket.assigns[:current_user] do
      Sessions.delete_session(id, user.id)
    end

    socket = refresh_sessions(socket)

    # Deleting the session that is open (or streaming into) leaves nothing to
    # show — navigate to a fresh conversation.
    if socket.assigns.session_id == id do
      {:noreply, push_patch(socket, to: ~p"/admin/deep_research")}
    else
      {:noreply, socket}
    end
  end

  defp cancel_current_run(socket) do
    cancel_run_async(socket.assigns.thread_id, socket.assigns.run_id)

    socket
    |> cancel_async(:research)
    |> update_current_turn(fn turn ->
      %{turn | phase: :cancelled, finished_at: turn.finished_at || now_ms()}
    end)
    |> assign(running: false)
  end

  defp start_research(socket, text) do
    id = socket.assigns.next_id
    now = now_ms()
    turn = Timeline.new_turn(text, id, now)
    lv = self()
    thread_id = socket.assigns.thread_id
    # Pure, in-memory: which MCP servers are toggled on. Auth resolution (a DB
    # read) is deferred into the async task so the LiveView process never blocks.
    enabled_mcp = enabled_mcp_servers(socket)
    model_tier = socket.assigns.model_tier
    user = socket.assigns[:current_user]

    # Everything network/DB-bound runs off the socket via start_async/3 (like
    # AskLive) so the LiveView keeps serving heartbeats; incremental events
    # arrive as {:dra_event, ref, _} messages, the terminal status via handle_async/3.
    socket
    |> persist_new_turn(turn)
    |> assign(
      # The turn that just finished (if any) is now history — moving it out of
      # :current_turn is what stops it re-rendering for the rest of the session.
      turns: archive_current_turn(socket),
      current_turn: turn,
      running: true,
      query: "",
      run_id: nil,
      # A warning belongs to the run that produced it; a new run starts clean.
      mcp_warning: nil,
      next_id: id + 1,
      now_ms: now
    )
    |> schedule_tick()
    |> start_async(:research, fn ->
      run_stream(thread_id, text, lv, enabled_mcp, user, model_tier, id)
    end)
  end

  defp archive_current_turn(%{assigns: %{current_turn: nil, turns: turns}}), do: turns
  defp archive_current_turn(%{assigns: %{current_turn: turn, turns: turns}}), do: turns ++ [turn]

  # Persist the new turn (and, on the first turn, the session row) before the
  # run starts, so a browser closed mid-run still leaves the question behind.
  # A persistence failure must never block research — log and carry on.
  defp persist_new_turn(socket, turn) do
    case {socket.assigns[:current_user], socket.assigns.session_id} do
      {nil, _} ->
        socket

      {_user, session_id} when is_binary(session_id) ->
        with {:error, error} <- Sessions.create_turn(session_id, turn, socket.assigns.model_tier) do
          log_persist_error("create_turn", error)
        end

        socket

      {user, nil} ->
        case Sessions.start_session(user.id, socket.assigns.model_tier, turn) do
          {:ok, %{session: session}} ->
            # The URL becomes the session's permalink the moment it exists, so
            # it can be copied mid-run. handle_params recognizes the id it
            # already holds and leaves the streaming state alone.
            socket
            |> assign(:session_id, session.id)
            |> refresh_sessions()
            |> push_patch(to: ~p"/admin/deep_research/#{session.id}")

          {:error, error} ->
            log_persist_error("start_session", error)
            socket
        end
    end
  end

  # Write the turn's row once it settles (terminal phase or :awaiting_user); a
  # follow-up settled change (e.g. finalize stamping finished_at after a
  # clarification) re-writes, an unchanged turn never does.
  defp maybe_persist_settled(socket, prev, next) do
    if socket.assigns.session_id && Timeline.settled_phase?(next.phase) && next != prev do
      with {:error, error} <- Sessions.update_turn(socket.assigns.session_id, next.id, next) do
        log_persist_error("update_turn", error)
      end

      Sessions.touch_session(socket.assigns.session_id)
      # touch_session just changed the sidebar ordering.
      refresh_sessions(socket)
    else
      socket
    end
  end

  defp refresh_sessions(socket) do
    user = socket.assigns[:current_user]

    # Skip the query on the static (disconnected) render — the connected mount
    # runs it again anyway.
    sessions =
      if user && connected?(socket), do: Sessions.list_user_sessions(user.id), else: []

    assign(socket, :sessions, sessions)
  end

  defp log_persist_error(operation, error) do
    Logger.warning("Deep research session persistence failed in #{operation}: #{inspect(error)}")
  end

  # The enabled catalog entries — pure, runs in the LiveView process (no DB/IO).
  defp enabled_mcp_servers(socket) do
    Enum.filter(socket.assigns.mcp_catalog, &MapSet.member?(socket.assigns.mcp_enabled, &1.key))
  end

  defp tier_hint(tiers, selected) do
    case List.keyfind(tiers, selected, 0) do
      {_, _, hint} -> hint
      nil -> nil
    end
  end

  # Runs INSIDE the async task (off the LiveView process): resolve MCP auth (a
  # DB read), create the thread on the first turn, then stream. Returns the
  # terminal status, handled by handle_async/3.
  defp run_stream(thread_id, text, lv, enabled_mcp, user, model_tier, ref) do
    mcp_servers = build_mcp_servers(enabled_mcp, user)

    do_run_stream(thread_id, text, lv,
      mcp_servers: mcp_servers,
      model_tier: model_tier,
      ref: ref
    )
  end

  defp do_run_stream(nil, text, lv, opts) do
    case Client.create_thread() do
      {:ok, thread_id} ->
        send(lv, {:dra_thread, thread_id})
        Client.stream_run(thread_id, text, lv, opts)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp do_run_stream(thread_id, text, lv, opts) when is_binary(thread_id) do
    Client.stream_run(thread_id, text, lv, opts)
  end

  # Build agent MCP server maps from the enabled catalog entries, resolving
  # `:user_apikey` auth to the user's Santiment API key. Runs in the async task.
  defp build_mcp_servers([], _user), do: []

  defp build_mcp_servers(enabled, user) do
    api_key = resolve_api_key(enabled, user)
    enabled |> Enum.map(&agent_server(&1, api_key)) |> Enum.reject(&is_nil/1)
  end

  defp resolve_api_key(enabled, user) do
    if Enum.any?(enabled, &(&1.auth == :user_apikey)) do
      case fetch_api_key(user) do
        {:ok, key} -> key
        _ -> nil
      end
    end
  end

  defp agent_server(%{auth: :user_apikey} = server, api_key) do
    case apikey_override(server) || api_key do
      key when is_binary(key) ->
        %{
          "name" => server.label,
          "label" => server.label,
          "url" => server.url,
          "tools" => [],
          "headers" => %{"Authorization" => "Apikey #{key}"}
        }

      # No API key available — skip a server that needs one.
      _ ->
        nil
    end
  end

  defp agent_server(server, _api_key) do
    %{"name" => server.label, "label" => server.label, "url" => server.url, "tools" => []}
  end

  defp apikey_override(server) do
    case Map.get(server, :apikey_override) do
      override when is_binary(override) and override != "" -> override
      _ -> nil
    end
  end

  defp fetch_api_key(%Sanbase.Accounts.User{} = user) do
    case Sanbase.Accounts.Apikey.apikeys_list(user) do
      {:ok, [key | _]} -> {:ok, key}
      {:ok, []} -> Sanbase.Accounts.Apikey.generate_apikey(user)
      other -> other
    end
  end

  defp fetch_api_key(_), do: {:error, :no_user}

  # -- streamed messages -------------------------------------------------------

  @impl true
  def handle_info({:dra_thread, thread_id}, socket) do
    socket =
      if is_nil(socket.assigns.thread_id) do
        if socket.assigns.session_id,
          do: Sessions.set_thread_id(socket.assigns.session_id, thread_id)

        assign(socket, :thread_id, thread_id)
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_info({:dra_event, ref, result}, socket) do
    # Two ways an event can be stale, both of which would corrupt a live turn:
    # a ref from a superseded run (see the moduledoc), or an event queued behind
    # a terminal status — dropping the latter stops a cancelled turn from
    # growing new thinking/tools or being handed a late report.
    if stale_ref?(socket, ref) or current_turn_terminal?(socket) do
      {:noreply, socket}
    else
      socket =
        socket
        |> apply_socket_level(result)
        |> update_current_turn(&Timeline.apply_result(&1, result))

      {:noreply, socket}
    end
  end

  # Poll-state fallback after a no-report stream close: recover a report from the
  # thread state if present, otherwise fail the turn with an explanation. The poll
  # can take up to 30s, by which time the user may have asked something else —
  # hence the ref check, without which this would fail the *new* turn.
  def handle_info({:dra_poll, ref, result}, socket) do
    if stale_ref?(socket, ref) do
      {:noreply, socket}
    else
      socket =
        update_current_turn(socket, fn turn ->
          cond do
            turn.phase in [:failed, :cancelled, :awaiting_user] ->
              turn

            turn.report ->
              %{turn | phase: :completed, finished_at: turn.finished_at || now_ms()}

            is_binary(result[:report]) ->
              %{
                turn
                | report: result[:report],
                  phase: :completed,
                  finished_at: turn.finished_at || now_ms()
              }

            true ->
              fail_no_report(turn)
          end
        end)

      {:noreply, socket}
    end
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

  defp finalize_run(%{assigns: %{running: false}} = socket), do: socket

  defp finalize_run(socket) do
    socket = assign(socket, running: false)
    turn = socket.assigns.current_turn

    cond do
      is_nil(turn) ->
        socket

      # A report was delivered, the turn already ended in a known state (failed
      # via a `status: error`, cancelled, or awaiting a clarification), or the
      # agent answered conversationally in plain text (a follow-up/simple
      # question — no report is expected, so it is NOT a missing-report failure).
      turn.report || turn.phase in [:failed, :cancelled, :awaiting_user] ||
          Timeline.direct_answer?(turn) ->
        update_current_turn(socket, &finalize_turn/1)

      # The stream closed with NO report and no explicit error. Poll the thread
      # state as a fallback; the {:dra_poll, _, _} handler then either completes
      # the turn (report recovered) or fails it with an explanation.
      socket.assigns.thread_id ->
        poll_state_async(socket.assigns.thread_id, self(), turn.id)
        update_current_turn(socket, fn t -> %{t | finished_at: t.finished_at || now_ms()} end)

      true ->
        update_current_turn(socket, &fail_no_report/1)
    end
  end

  # A run that ends without ever delivering a report is a failure — show why.
  # Keep any error reason the agent already surfaced (e.g. a `status: error`
  # detail); otherwise explain the missing report.
  defp fail_no_report(turn) do
    %{
      turn
      | phase: :failed,
        error: turn.error || @no_report_error,
        finished_at: turn.finished_at || now_ms()
    }
  end

  defp fail_run(socket, reason) do
    if socket.assigns.running do
      socket
      |> update_current_turn(fn turn ->
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

  # A message is stale when it belongs to any turn other than the current one.
  defp stale_ref?(%{assigns: %{current_turn: %{id: id}}}, ref), do: ref != id
  defp stale_ref?(_socket, _ref), do: true

  defp current_turn_terminal?(%{assigns: %{current_turn: %{phase: phase}}}),
    do: Timeline.terminal_phase?(phase)

  defp current_turn_terminal?(_socket), do: false

  defp update_current_turn(%{assigns: %{current_turn: nil}} = socket, _fun), do: socket

  # The single choke point every turn mutation flows through (stream events,
  # poll, cancel, finalize, fail) — which makes it the one place persistence
  # has to watch for a turn settling.
  defp update_current_turn(socket, fun) do
    prev = socket.assigns.current_turn
    next = fun.(prev)

    socket
    |> assign(:current_turn, next)
    |> maybe_persist_settled(prev, next)
  end

  defp poll_state_async(thread_id, lv, ref) do
    Task.Supervisor.start_child(Sanbase.TaskSupervisor, fn ->
      result =
        case Client.get_state(thread_id) do
          {:ok, state} -> EventParser.parse_thread_state(state)
          _ -> %{}
        end

      # Always reply so the LiveView can finalize (recover report or fail).
      send(lv, {:dra_poll, ref, result})
    end)
  end

  defp cancel_run_async(thread_id, run_id) when is_binary(thread_id) and is_binary(run_id) do
    Task.Supervisor.start_child(Sanbase.TaskSupervisor, fn ->
      Client.cancel_run(thread_id, run_id)
    end)
  end

  # Cancel arrived before the stream delivered a run_id: the server-side run
  # already exists, so cancel whatever is active on the thread — otherwise it
  # keeps running (and billing) invisibly after the UI shows "cancelled".
  defp cancel_run_async(thread_id, nil) when is_binary(thread_id) do
    Task.Supervisor.start_child(Sanbase.TaskSupervisor, fn ->
      Client.cancel_active_runs(thread_id)
    end)
  end

  # No thread yet (cancel raced thread creation) — nothing server-side to cancel.
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
    <div class="mx-auto flex h-[calc(100vh-10rem)] w-full max-w-7xl gap-6 px-4">
      <.sidebar sessions={@sessions} current_session_id={@session_id} running={@running} />
      <div class="flex min-h-0 min-w-0 flex-1 flex-col">
        <div
          :if={@turns == [] and is_nil(@current_turn)}
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

        <div
          :if={@turns != [] or @current_turn}
          class="min-h-0 flex-1 space-y-8 overflow-y-auto py-4"
        >
          <%!-- Finished turns carry their own finished_at, so they take no now_ms and
                stay untouched while the current turn streams. --%>
          <.turn_view :for={turn <- @turns} turn={turn} running={false} />
          <.turn_view :if={@current_turn} turn={@current_turn} running={@running} now_ms={@now_ms} />
        </div>

        <div class="shrink-0 pt-2">
          <div
            :if={@tiering_dropdown_enabled or @mcp_catalog != []}
            class="mb-2 flex flex-wrap items-center gap-2 px-1"
          >
            <span
              :if={@tiering_dropdown_enabled}
              class="text-[11px] font-medium uppercase tracking-wide text-base-content/40"
            >
              Model tier
            </span>
            <form :if={@tiering_dropdown_enabled} phx-change="select_tier">
              <select
                name="model_tier"
                title={tier_hint(@model_tiers, @model_tier)}
                class="rounded-full border border-base-300 bg-base-100 px-2.5 py-1 text-xs text-base-content/70 transition hover:border-base-content/20 focus:outline-none"
              >
                <option
                  :for={{value, label, hint} <- @model_tiers}
                  value={value}
                  selected={value == @model_tier}
                >
                  {label} — {hint}
                </option>
              </select>
            </form>
            <span
              :if={@mcp_catalog != []}
              class={[
                "text-[11px] font-medium uppercase tracking-wide text-base-content/40",
                @tiering_dropdown_enabled && "ml-2"
              ]}
            >
              Data sources
            </span>
            <button
              :for={server <- @mcp_catalog}
              type="button"
              phx-click="toggle_mcp"
              phx-value-key={server.key}
              aria-pressed={MapSet.member?(@mcp_enabled, server.key)}
              title={"Connect the agent to #{server.label} MCP tools"}
              class={[
                "inline-flex items-center gap-1.5 rounded-full border px-2.5 py-1 text-xs transition",
                if(MapSet.member?(@mcp_enabled, server.key),
                  do: "border-primary/40 bg-primary/10 text-primary",
                  else:
                    "border-base-300 text-base-content/50 hover:border-base-content/20 hover:text-base-content"
                )
              ]}
            >
              <.icon name="hero-circle-stack" class="size-3.5" />
              {server.label}
              <span
                :if={MapSet.member?(@mcp_enabled, server.key)}
                class="size-1.5 rounded-full bg-success"
              ></span>
            </button>
          </div>
          <p :if={@mcp_warning} class="mb-2 px-1 text-xs text-warning" role="status">
            {@mcp_warning}
          </p>
          <.composer
            query={@query}
            running={@running}
            placeholder={
              if @turns == [] and is_nil(@current_turn),
                do: "Ask anything about crypto markets, assets, on-chain & social metrics…",
                else: "Reply, or ask a follow-up…"
            }
          />
          <p class="mt-2 text-center text-[11px] text-base-content/40">
            Deep research runs can take a few minutes · responses include cited sources
          </p>
        </div>
      </div>
    </div>
    """
  end

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
