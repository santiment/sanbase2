defmodule SanbaseWeb.DeepResearchLive do
  @moduledoc """
  Deep research agent UI. Holds only socket/UI state; the lifecycle lives in a
  detached `Sanbase.DeepResearch.Runner` this LiveView attaches to and mirrors, so a
  websocket drop leaves the run streaming — reattached on remount, or left `:paused`
  for the owner to Continue.

  `:turns` (finished) is split from `:current_turn` so a stream event re-renders one
  turn, not the transcript.
  """
  use SanbaseWeb, :live_view

  require Logger

  import SanbaseWeb.DeepResearch.Components, only: [composer: 1, turn_view: 1, sidebar: 1]

  alias Sanbase.DeepResearch.{Config, Failure, Runner, Sessions, Timeline, Turn}

  @impl true
  def mount(_params, _session, socket) do
    catalog = Config.mcp_catalog()

    socket =
      socket
      |> assign(
        mcp_catalog: catalog,
        mcp_enabled: MapSet.new(Enum.map(catalog, & &1.key)),
        # Price tier, the only per-run model knob. Flagged off = deploy default.
        tiering_dropdown_enabled: Config.tiering_dropdown_enabled?(),
        model_tiers: Config.model_tiers(),
        model_tier: Config.default_model_tier(),
        # Outside reset_conversation/1: a pending timer survives a reset.
        tick_scheduled?: false
      )
      |> reset_conversation()
      |> refresh_sessions()

    {:ok, socket}
  end

  # Mount and every push_patch. Navigating away only DETACHES; the run keeps going.
  @impl true
  def handle_params(params, _uri, socket) do
    if params["id"] && params["id"] == socket.assigns.session_id do
      # Our own patch for the session already held — reloading destroys a live run.
      {:noreply, socket}
    else
      socket = detach_runner(socket)

      case socket.assigns.live_action do
        :show -> open_session(socket, params["id"])
        _ -> {:noreply, reset_conversation(socket)}
      end
    end
  end

  # A live runner (reconnect, second tab) reattaches here, so its snapshot replaces
  # the loaded row of the turn it still streams.
  defp open_session(socket, session_id) do
    user = socket.assigns[:current_user]

    case user && Sessions.get_session_for_user(session_id, user.id) do
      {:ok, %{session: session, turns: turns}} ->
        socket =
          socket
          |> reset_conversation()
          |> assign(
            turns: turns,
            session_id: session.id,
            thread_id: session.thread_id,
            next_id: next_position(turns)
          )

        {:noreply, attach_runner(socket, session.id, Runner.whereis(session.id))}

      # :forbidden collapses into "not found". push_navigate: this runs on mount too.
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
      running: false,
      query: "",
      mcp_warning: nil,
      next_id: 1,
      session_id: nil,
      runner_pid: nil,
      runner_ref: nil,
      runner_key: nil,
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
    # A crafted event must not change the tier when the dropdown is off.
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

  # A cancel with nothing in flight must not touch the finished turn.
  def handle_event("cancel", _params, %{assigns: %{running: false}} = socket),
    do: {:noreply, socket}

  def handle_event("cancel", _params, socket) do
    case socket.assigns.runner_pid && Runner.cancel(socket.assigns.runner_pid) do
      {:ok, snapshot} -> {:noreply, apply_snapshot(socket, snapshot)}
      _ -> {:noreply, assign(socket, :running, false)}
    end
  end

  def handle_event("continue_turn", _params, %{assigns: %{running: true}} = socket),
    do: {:noreply, socket}

  def handle_event("continue_turn", %{"id" => id}, socket) do
    case continuable_turn(socket, id) do
      %Turn{} = turn -> {:noreply, resume_research(socket, turn)}
      nil -> {:noreply, socket}
    end
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
    # Stop the runner only AFTER delete_session's owner check.
    with %{} = user <- socket.assigns[:current_user],
         {:ok, _session} <- Sessions.delete_session(id, user.id),
         pid when is_pid(pid) <- Runner.whereis(id) do
      Runner.shutdown(pid)
    end

    socket = refresh_sessions(socket)

    if socket.assigns.session_id == id do
      {:noreply, push_patch(socket, to: ~p"/admin/deep_research")}
    else
      {:noreply, socket}
    end
  end

  # -- runner plumbing -----------------------------------------------------------

  # Only the LAST turn can be continued — the thread has moved past earlier ones.
  defp continuable_turn(socket, id_param) do
    last = socket.assigns.current_turn || List.last(socket.assigns.turns)

    with %Turn{phase: :paused} = turn <- last,
         {id, ""} <- Integer.parse(to_string(id_param)),
         true <- turn.id == id do
      turn
    else
      _ -> nil
    end
  end

  defp start_research(socket, text) do
    socket = socket |> ensure_session(text) |> ensure_runner()

    case socket.assigns.runner_pid &&
           Runner.ask(socket.assigns.runner_pid, text, run_opts(socket)) do
      {:ok, snapshot} ->
        socket |> assign(:query, "") |> apply_snapshot(snapshot)

      # Another tab already started a run on this session.
      {:error, :busy} ->
        socket

      _ ->
        put_flash(socket, :error, "Could not start the research run — please retry.")
    end
  end

  defp resume_research(socket, turn) do
    socket = ensure_runner(socket)

    case socket.assigns.runner_pid &&
           Runner.continue(socket.assigns.runner_pid, turn, run_opts(socket)) do
      {:ok, snapshot} -> apply_snapshot(socket, snapshot)
      {:error, :busy} -> socket
      _ -> put_flash(socket, :error, "Could not resume the research — please retry.")
    end
  end

  defp run_opts(socket) do
    [
      enabled_mcp: enabled_mcp_servers(socket),
      model_tier: socket.assigns.model_tier
    ]
  end

  # The first question creates the row (registry key, persistence, permalink); on
  # failure the conversation continues unpersisted rather than blocking research.
  defp ensure_session(%{assigns: %{session_id: id}} = socket, _text) when is_binary(id),
    do: socket

  defp ensure_session(socket, text) do
    user = socket.assigns[:current_user]

    case user && Sessions.create_session(user.id, socket.assigns.model_tier, text) do
      {:ok, session} ->
        socket
        |> assign(:session_id, session.id)
        |> refresh_sessions()
        |> push_patch(to: ~p"/admin/deep_research/#{session.id}")

      {:error, error} ->
        Logger.warning("Deep research session creation failed: #{inspect(error)}")
        socket

      nil ->
        socket
    end
  end

  defp ensure_runner(%{assigns: %{runner_pid: pid}} = socket) when is_pid(pid), do: socket

  defp ensure_runner(socket) do
    key = socket.assigns.session_id || ephemeral_key()

    init_arg = %{
      key: key,
      session_id: socket.assigns.session_id,
      user: socket.assigns[:current_user],
      model_tier: socket.assigns.model_tier,
      thread_id: socket.assigns.thread_id,
      next_id: socket.assigns.next_id
    }

    case Runner.ensure_started(init_arg) do
      {:ok, pid} ->
        attach_runner(socket, key, pid)

      {:error, error} ->
        Logger.warning("Deep research runner failed to start: #{inspect(error)}")
        socket
    end
  end

  # No runner, or it stopped between lookup and attach — the transcript is authoritative.
  defp attach_runner(socket, _key, nil), do: socket

  defp attach_runner(socket, key, pid) do
    case Runner.attach(pid, self()) do
      {:ok, snapshot} ->
        socket
        |> assign(runner_pid: pid, runner_ref: Process.monitor(pid), runner_key: key)
        |> apply_snapshot(snapshot)

      {:error, :not_alive} ->
        socket
    end
  end

  defp detach_runner(%{assigns: %{runner_pid: nil}} = socket), do: socket

  defp detach_runner(socket) do
    Process.demonitor(socket.assigns.runner_ref, [:flush])
    Runner.detach(socket.assigns.runner_pid, self())
    forget_runner(socket)
  end

  defp forget_runner(socket) do
    assign(socket, runner_pid: nil, runner_ref: nil, runner_key: nil)
  end

  # An anonymous conversation gets a runner too, under a key no URL can find again.
  defp ephemeral_key(), do: "ephemeral-#{System.unique_integer([:positive])}"

  defp apply_snapshot(socket, snapshot) do
    was_running = socket.assigns.running

    socket =
      assign(socket,
        turns: settled_turns(socket, snapshot.current_turn),
        current_turn: snapshot.current_turn || socket.assigns.current_turn,
        running: snapshot.running,
        mcp_warning: snapshot.mcp_warning,
        thread_id: snapshot.thread_id || socket.assigns.thread_id,
        next_id: max(socket.assigns.next_id, snapshot.next_id),
        now_ms: now_ms()
      )

    socket = if snapshot.running, do: schedule_tick(socket), else: socket

    # A run just settled: touch_session changed the sidebar ordering.
    if was_running and not snapshot.running, do: refresh_sessions(socket), else: socket
  end

  # The transcript minus the turn the runner owns (a reattach loaded its row too); a
  # turn the runner moved past rejoins it.
  defp settled_turns(socket, nil), do: socket.assigns.turns

  defp settled_turns(socket, runner_turn) do
    prev = socket.assigns.current_turn
    kept = Enum.reject(socket.assigns.turns, &(&1.id == runner_turn.id))

    if prev && prev.id != runner_turn.id, do: kept ++ [prev], else: kept
  end

  defp refresh_sessions(socket) do
    user = socket.assigns[:current_user]

    # Skip the query on the static render; the connected mount runs it anyway.
    sessions =
      if user && connected?(socket), do: Sessions.list_user_sessions(user.id), else: []

    assign(socket, :sessions, sessions)
  end

  defp enabled_mcp_servers(socket) do
    Enum.filter(socket.assigns.mcp_catalog, &MapSet.member?(socket.assigns.mcp_enabled, &1.key))
  end

  defp tier_hint(tiers, selected) do
    case List.keyfind(tiers, selected, 0) do
      {_, _, hint} -> hint
      nil -> nil
    end
  end

  # -- runner messages -----------------------------------------------------------

  # A snapshot from a runner we no longer follow falls through to the catch-all below.
  @impl true
  def handle_info({:dra_runner, key, snapshot}, %{assigns: %{runner_key: key}} = socket),
    do: {:noreply, apply_snapshot(socket, snapshot)}

  # A clean stop already settled the turn.
  def handle_info({:DOWN, ref, :process, _pid, :normal}, %{assigns: %{runner_ref: ref}} = socket),
    do: {:noreply, forget_runner(socket)}

  # A crash settled nothing: park the turn :paused locally, with the reason, so the
  # tab says what interrupted the research instead of going quiet.
  def handle_info({:DOWN, ref, :process, _pid, reason}, %{assigns: %{runner_ref: ref}} = socket) do
    why = Failure.crashed(reason).message

    socket =
      socket
      |> forget_runner()
      |> assign(:running, false)
      |> update(:current_turn, &(&1 && Timeline.pause_turn(&1, now_ms(), why)))

    {:noreply, socket}
  end

  def handle_info(:tick, socket) do
    socket = assign(socket, :tick_scheduled?, false)

    if socket.assigns.running do
      {:noreply, socket |> assign(:now_ms, now_ms()) |> schedule_tick()}
    else
      {:noreply, socket}
    end
  end

  # Snapshots or :DOWN from a dropped runner, plus late `{ref, reply}` replies to a
  # timed-out Runner.safe_call/2.
  def handle_info(_msg, socket), do: {:noreply, socket}

  # At most one :tick in flight; a leftover timer would start a second loop.
  defp schedule_tick(%{assigns: %{tick_scheduled?: true}} = socket), do: socket

  defp schedule_tick(socket) do
    Process.send_after(self(), :tick, 1000)
    assign(socket, :tick_scheduled?, true)
  end

  defp now_ms(), do: System.system_time(:millisecond)

  # -- render ------------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto flex h-[calc(100vh-10rem)] w-full max-w-7xl gap-6 px-4">
      <.sidebar sessions={@sessions} current_session_id={@session_id} />
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
          <.turn_view
            :for={turn <- @turns}
            turn={turn}
            running={false}
            can_continue={is_nil(@current_turn) and not @running and turn == List.last(@turns)}
          />
          <.turn_view
            :if={@current_turn}
            turn={@current_turn}
            running={@running}
            now_ms={@now_ms}
            can_continue={not @running}
          />
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
