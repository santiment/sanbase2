defmodule Sanbase.DeepResearch.Runner do
  @moduledoc """
  Run engine of a deep research session, detached from any LiveView. One runner per
  session in `Sanbase.DeepResearch.Registry`: streams the run, folds events into the
  current `Turn` (`ref` = turn id; others are stale), persists settled turns plus a
  periodic checkpoint of the one in flight, and pushes `{:dra_runner, key, snapshot}`
  to watchers.

  It outlives its watchers, so a reconnect reattaches mid-stream. Unwatched for
  `Config.pause_after_disconnect_ms/0` it parks the turn `:paused` (resume with
  `continue/3`) and stops; idle it stops at once. The registry is node-local, so a
  reconnect on another node sees `:paused`.
  """

  use GenServer, restart: :temporary

  require Logger

  alias Sanbase.DeepResearch.{
    Client,
    Config,
    EventParser,
    Failure,
    McpServers,
    Sessions,
    Timeline,
    Turn
  }

  @registry Sanbase.DeepResearch.Registry
  @supervisor Sanbase.DeepResearch.RunnerSupervisor

  @continue_message "Continue the interrupted research. Pick up where you left off, reuse the " <>
                      "work already done on this thread, and deliver the final report."

  # The agent reports its own end states (budget, stall, error) as a `status` event, so a
  # run that ends with neither report nor reason most likely lost its server mid-run.
  @no_report_error "The research run ended without a report and without the agent saying why — " <>
                     "most likely the agent server restarted or dropped the connection mid-run. " <>
                     "Try again; if it keeps happening, narrow the question."

  # Still `:queued` when the stream ended: no worker ever picked the run up, so no agent
  # code ran and nothing about the question explains it.
  @never_started_error "The agent server never started this run: it stayed queued until the " <>
                         "connection ended. The server was probably restarting, or all of its " <>
                         "worker slots were busy — try again in a moment."

  defstruct [
    :key,
    :session_id,
    :user,
    :model_tier,
    :thread_id,
    :run_id,
    :current_turn,
    :task,
    :pause_timer,
    :silence_timer,
    :checkpointed_at,
    running: false,
    mcp_warning: nil,
    next_id: 1,
    watchers: %{}
  ]

  @type snapshot :: %{
          key: String.t(),
          session_id: Ecto.UUID.t() | nil,
          thread_id: String.t() | nil,
          current_turn: Turn.t() | nil,
          running: boolean(),
          mcp_warning: String.t() | nil,
          next_id: pos_integer()
        }

  # -- public API ----------------------------------------------------------------

  @doc """
  Start (or find) the runner for `init_arg.key`. Keys: `:key`, `:session_id`
  (nil = unpersisted), `:user`, `:model_tier`, `:thread_id`, `:next_id`.
  """
  @spec ensure_started(map()) :: {:ok, pid()} | {:error, term()}
  def ensure_started(init_arg) do
    case DynamicSupervisor.start_child(@supervisor, {__MODULE__, init_arg}) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      other -> other
    end
  end

  # Via `ensure_started/1` only — a runner outside the supervisor is not restarted
  # and not found by `whereis/1`.
  @doc false
  @spec start_link(map()) :: GenServer.on_start()
  def start_link(init_arg) do
    GenServer.start_link(__MODULE__, init_arg, name: via(init_arg.key))
  end

  @doc "The runner registered under `key`, or nil."
  @spec whereis(String.t() | nil) :: pid() | nil
  def whereis(nil), do: nil

  def whereis(key) do
    case Registry.lookup(@registry, key) do
      [{pid, _}] -> pid
      [] -> nil
    end
  end

  @doc "Attach `watcher` (monitored); returns the current snapshot."
  @spec attach(pid(), pid()) :: {:ok, snapshot()} | {:error, :not_alive}
  def attach(pid, watcher), do: safe_call(pid, {:attach, watcher})

  @doc "Detach `watcher`. With none left the runner pauses after a grace period."
  @spec detach(pid(), pid()) :: :ok
  def detach(pid, watcher), do: GenServer.cast(pid, {:detach, watcher})

  @doc """
  Ask `text` — how every turn starts, first or follow-up.

  Settles the previous turn if a run left it unsettled (nothing else will, once
  `:current_turn` moves on), opens turn `next_id` as `:queued`, inserts its row
  when the session is persisted — so a tab closed mid-run still leaves the question
  behind — and starts the stream task. The rest is asynchronous: the task creates
  the thread if needed and streams `{:dra_event, turn_id, _}` back.

  `opts`:

    * `:enabled_mcp` — catalog entries to connect (see `McpServers`);
    * `:model_tier` — price tier, remembered until the next `ask/3` changes it.

  Replies with the post-start snapshot and broadcasts it, so a second tab renders
  the new turn. `{:error, :busy}` while a run streams — one run per session.
  """
  @spec ask(pid(), String.t(), keyword()) ::
          {:ok, snapshot()} | {:error, :busy | :not_alive}
  def ask(pid, text, opts \\ []), do: safe_call(pid, {:ask, text, opts})

  @doc """
  Resume a `:paused` `turn` instead of asking a new one: a continue-run on the same
  thread streams INTO it (same id, phase back to `:queued`, error cleared), so its
  partial timeline keeps growing.

  Any run still live server-side is cancelled first — the crashed runner never got
  to. With no thread there is nothing to pick up, so the question is re-asked. Same
  `opts` as `ask/3`; `{:error, :not_paused}` in any other phase.
  """
  @spec continue(pid(), Turn.t(), keyword()) ::
          {:ok, snapshot()} | {:error, :busy | :not_paused | :not_alive}
  def continue(pid, %Turn{} = turn, opts \\ []), do: safe_call(pid, {:continue, turn, opts})

  @doc "Cancel the in-flight run (the user's Stop button)."
  @spec cancel(pid()) :: {:ok, snapshot()} | {:error, :not_alive}
  def cancel(pid), do: safe_call(pid, :cancel)

  @doc "Cancel any in-flight run and stop the runner (session deleted)."
  @spec shutdown(pid()) :: :ok
  def shutdown(pid), do: GenServer.cast(pid, :shutdown)

  # A runner can stop between lookup and call — don't take the caller down.
  defp safe_call(pid, msg) do
    GenServer.call(pid, msg)
  catch
    :exit, _ -> {:error, :not_alive}
  end

  defp via(key), do: {:via, Registry, {@registry, key}}

  # -- GenServer -------------------------------------------------------------------

  @impl true
  def init(init_arg) do
    # So terminate/2 runs and stops the stream task.
    Process.flag(:trap_exit, true)

    {:ok,
     %__MODULE__{
       key: init_arg.key,
       session_id: init_arg[:session_id],
       user: init_arg[:user],
       model_tier: init_arg[:model_tier],
       thread_id: init_arg[:thread_id],
       next_id: init_arg[:next_id] || 1
     }}
  end

  @impl true
  def handle_call({:attach, watcher}, _from, state) do
    watchers = Map.put_new_lazy(state.watchers, watcher, fn -> Process.monitor(watcher) end)
    state = cancel_pause_timer(%{state | watchers: watchers})

    {:reply, {:ok, snapshot(state)}, state}
  end

  def handle_call({:ask, _text, _opts}, _from, %{running: true} = state),
    do: {:reply, {:error, :busy}, state}

  def handle_call({:ask, text, opts}, _from, state) do
    # Nothing settles the old turn once :current_turn changes.
    state = settle_abandoned_turn(state)

    # Before persist_new_turn, so the row records the tier the run uses.
    state = %{state | model_tier: Keyword.get(opts, :model_tier, state.model_tier)}

    turn = Timeline.new_turn(text, state.next_id, now_ms())
    persist_new_turn(state, turn)

    state =
      state
      |> start_run(turn, text, opts)
      |> Map.update!(:next_id, &(&1 + 1))

    {:reply, {:ok, snapshot(state)}, broadcast(state)}
  end

  def handle_call({:continue, _turn, _opts}, _from, %{running: true} = state),
    do: {:reply, {:error, :busy}, state}

  def handle_call({:continue, %Turn{phase: :paused} = turn, opts}, _from, state) do
    # Same stranding as :ask — once :current_turn moves on, a pending poll reply no
    # longer matches its id.
    state =
      if state.current_turn && state.current_turn.id != turn.id,
        do: settle_abandoned_turn(state),
        else: state

    # `Map.merge` for the stream-only keys: a turn held since before a hot code reload
    # may predate them.
    resumed =
      %{turn | phase: :queued, finished_at: nil, error: nil}
      |> Map.merge(%{live: nil, last_event_at: nil})

    # No thread: nothing to resume, so re-ask the question.
    message = if state.thread_id, do: @continue_message, else: turn.question

    state =
      %{state | next_id: max(state.next_id, turn.id + 1)}
      |> start_run(resumed, message, opts)

    {:reply, {:ok, snapshot(state)}, broadcast(state)}
  end

  def handle_call({:continue, _turn, _opts}, _from, state),
    do: {:reply, {:error, :not_paused}, state}

  def handle_call(:cancel, _from, %{running: false} = state),
    do: {:reply, {:ok, snapshot(state)}, state}

  def handle_call(:cancel, _from, state) do
    state = cancel_current_run(state)
    {:reply, {:ok, snapshot(state)}, state}
  end

  @impl true
  def handle_cast({:detach, watcher}, state) do
    state = remove_watcher(state, watcher)
    maybe_wind_down(state)
  end

  def handle_cast(:shutdown, %{running: true} = state),
    do: {:stop, :normal, cancel_current_run(state)}

  def handle_cast(:shutdown, state), do: {:stop, :normal, state}

  # -- streamed messages -----------------------------------------------------------

  # The thread id arrives once, from the run that created the thread.
  @impl true
  def handle_info({:dra_thread, thread_id}, %{thread_id: nil} = state) do
    if state.session_id, do: Sessions.set_thread_id(state.session_id, thread_id)

    {:noreply, broadcast(%{state | thread_id: thread_id})}
  end

  def handle_info({:dra_thread, _thread_id}, state), do: {:noreply, state}

  # `ref` is the turn id; another turn's events belong to a superseded run and hit the
  # catch-all below. A terminal turn ignores events too — already settled.
  def handle_info({:dra_event, ref, result}, %{current_turn: %{id: ref, phase: phase}} = state) do
    if Timeline.terminal_phase?(phase) do
      {:noreply, state}
    else
      # Receipt time, so the UI can say how long the stream has been silent.
      result = Map.put_new(result, :at, now_ms())
      state = state |> apply_run_level(result) |> arm_silence_watchdog()
      {:noreply, update_current_turn(state, &Timeline.apply_result(&1, result))}
    end
  end

  # No event for `Config.event_silence_ms/0` while the stream is open. Heartbeats keep the
  # connection (and its idle timeout) alive after a run has died server-side, so ask the
  # server. An unknown run id (no metadata event yet) or a failed request says nothing:
  # keep waiting, re-armed.
  def handle_info(:event_silence, %{running: true} = state) do
    state = %{state | silence_timer: nil}

    if is_binary(state.thread_id) and is_binary(state.run_id) do
      check_run_status_async(state.thread_id, state.run_id, self(), state.current_turn.id)
    end

    {:noreply, arm_silence_watchdog(state)}
  end

  def handle_info(:event_silence, state), do: {:noreply, %{state | silence_timer: nil}}

  def handle_info(
        {:dra_run_status, ref, {:ok, run}},
        %{current_turn: %{id: ref}, running: true} = state
      ) do
    case run["status"] do
      status when status in ["pending", "running"] ->
        {:noreply, state}

      status ->
        # A zombie stream: the run is over server-side and nothing more will arrive.
        # `success` → the report is in the thread state; anything else → paused with the
        # reason, since the thread survives and Continue can pick it up.
        Logger.warning(
          "Deep research run #{state.run_id} is #{status} server-side while its stream stayed silent — settling the turn"
        )

        state = stop_task(state)

        state =
          if status == "success",
            do: finalize_run(state),
            else: fail_run(state, Failure.zombie(status))

        maybe_wind_down(state)
    end
  end

  def handle_info({:dra_run_status, _ref, _result}, state), do: {:noreply, state}

  # The poll could not be made — that says nothing about the run, so settle from the
  # failure rather than blaming the turn for delivering no report.
  def handle_info({:dra_poll, ref, %Failure{} = failure}, %{current_turn: %{id: ref}} = state) do
    state = update_current_turn(state, &settle_failure(&1, failure, now_ms()))

    maybe_wind_down(state)
  end

  def handle_info({:dra_poll, ref, result}, %{current_turn: %{id: ref}} = state) do
    state =
      update_current_turn(state, fn turn ->
        report = turn.report || result[:report]

        cond do
          Timeline.settled_phase?(turn.phase) -> turn
          is_binary(report) -> Timeline.complete_turn(%{turn | report: report}, now_ms())
          true -> fail_no_report(turn)
        end
      end)

    maybe_wind_down(state)
  end

  def handle_info({task_ref, result}, %{task: %Task{ref: task_ref}} = state) do
    Process.demonitor(task_ref, [:flush])
    state = %{state | task: nil}

    state =
      case result do
        :ok -> finalize_run(state)
        {:error, failure} -> fail_run(state, failure)
      end

    maybe_wind_down(state)
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, %{task: %Task{ref: ref}} = state) do
    state =
      %{state | task: nil}
      |> fail_run(Failure.crashed(reason))

    maybe_wind_down(state)
  end

  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    state = remove_watcher(state, pid)
    maybe_wind_down(state)
  end

  def handle_info(:pause_timeout, state) do
    if map_size(state.watchers) == 0 do
      {:stop, :normal, pause(state)}
    else
      # Re-attached as the timer fired.
      {:noreply, %{state | pause_timer: nil}}
    end
  end

  # Events for a superseded turn, and late replies from superseded tasks.
  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    stop_task(state)
    :ok
  end

  # -- run lifecycle ----------------------------------------------------------------

  # Anything still active on the thread when a turn starts is a leftover: this runner
  # considers the previous turn over (settled, cancelled, or paused by a crash that never
  # got to cancel), and the agent server resumes in-flight runs from disk after a restart
  # with no client attached. Left alone it would only park the new run in `pending`
  # behind it, so it is cancelled first.
  defp start_run(state, turn, message, opts) do
    sink = self()
    thread_id = state.thread_id
    enabled_mcp = Keyword.get(opts, :enabled_mcp, [])
    user = state.user
    model_tier = Keyword.get(opts, :model_tier, state.model_tier)
    ref = turn.id

    task =
      Task.Supervisor.async_nolink(Sanbase.TaskSupervisor, fn ->
        if is_binary(thread_id), do: Client.cancel_active_runs(thread_id)

        # Inside the task: resolving MCP servers does a DB read.
        stream_opts = [
          mcp_servers: McpServers.build(enabled_mcp, user),
          model_tier: model_tier,
          ref: ref
        ]

        stream_run(thread_id, message, sink, stream_opts)
      end)

    %{state | current_turn: turn, running: true, run_id: nil, mcp_warning: nil, task: task}
    |> arm_silence_watchdog()
  end

  defp arm_silence_watchdog(state) do
    if state.silence_timer, do: Process.cancel_timer(state.silence_timer)

    %{
      state
      | silence_timer: Process.send_after(self(), :event_silence, Config.event_silence_ms())
    }
  end

  # First run of a session: the thread has to exist before anything can stream.
  defp stream_run(nil, text, sink, opts) do
    with {:ok, thread_id} <- Client.create_thread() do
      send(sink, {:dra_thread, thread_id})
      Client.stream_run(thread_id, text, sink, opts)
    end
  end

  defp stream_run(thread_id, text, sink, opts) when is_binary(thread_id) do
    Client.stream_run(thread_id, text, sink, opts)
  end

  defp finalize_run(%{running: false} = state), do: state
  defp finalize_run(%{current_turn: nil} = state), do: broadcast(%{state | running: false})

  defp finalize_run(%{current_turn: turn} = state) do
    state = %{state | running: false}

    cond do
      turn.report || Timeline.settled_phase?(turn.phase) || Timeline.direct_answer?(turn) ->
        update_current_turn(state, &Timeline.complete_turn(&1, now_ms()))

      # No report, no error — {:dra_poll, _, _} settles it.
      state.thread_id ->
        poll_state_async(state.thread_id, self(), turn.id)
        update_current_turn(state, &Timeline.stamp_finished_at(&1, now_ms()))

      true ->
        update_current_turn(state, &fail_no_report/1)
    end
  end

  defp fail_run(%{running: false} = state, _failure), do: state

  defp fail_run(state, %Failure{} = failure) do
    %{state | running: false}
    |> update_current_turn(&settle_failure(&1, failure, now_ms()))
  end

  # A broken connection parks the turn `:paused`, not `:failed`: the agent still has
  # the thread, so `continue/3` can resume. Only its own refusals fail a turn. See
  # `DeepResearch.Failure`.
  defp settle_failure(turn, %Failure{resumable?: true} = failure, now_ms),
    do: Timeline.pause_turn(turn, now_ms, failure.message)

  defp settle_failure(turn, %Failure{} = failure, now_ms),
    do: Timeline.fail_turn(turn, failure.message, now_ms)

  defp fail_no_report(%{phase: :queued} = turn),
    do: Timeline.fail_turn(turn, @never_started_error, now_ms())

  defp fail_no_report(turn), do: Timeline.fail_turn(turn, @no_report_error, now_ms())

  defp settle_abandoned_turn(%{current_turn: %{phase: phase}} = state) do
    if Timeline.settled_phase?(phase),
      do: state,
      else: update_current_turn(state, &fail_no_report/1)
  end

  defp settle_abandoned_turn(state), do: state

  defp cancel_current_run(state), do: stop_run(state, &Timeline.cancel_turn(&1, now_ms()))

  defp stop_run(state, settle_fun) do
    if state.running, do: cancel_run_async(state.thread_id, state.run_id)

    %{stop_task(state) | running: false}
    |> update_current_turn(settle_fun)
  end

  # Its SSE connection would otherwise outlive the run.
  defp stop_task(%{task: nil} = state), do: state

  defp stop_task(state) do
    Task.shutdown(state.task, :brutal_kill)
    %{state | task: nil}
  end

  # -- pausing / winding down --------------------------------------------------------

  defp remove_watcher(state, watcher) do
    case Map.pop(state.watchers, watcher) do
      {nil, _} ->
        state

      {ref, watchers} ->
        Process.demonitor(ref, [:flush])
        %{state | watchers: watchers}
    end
  end

  # Nobody watching: an unfinished run gets the grace period, a settled one stops.
  defp maybe_wind_down(%{watchers: watchers} = state) when map_size(watchers) > 0,
    do: {:noreply, state}

  defp maybe_wind_down(%{current_turn: turn} = state) do
    if state.running or (turn && not Timeline.settled_phase?(turn.phase)),
      do: {:noreply, schedule_pause(state)},
      else: {:stop, :normal, state}
  end

  defp schedule_pause(%{pause_timer: nil} = state) do
    timer = Process.send_after(self(), :pause_timeout, Config.pause_after_disconnect_ms())
    %{state | pause_timer: timer}
  end

  defp schedule_pause(state), do: state

  defp cancel_pause_timer(%{pause_timer: nil} = state), do: state

  defp cancel_pause_timer(state) do
    Process.cancel_timer(state.pause_timer)
    %{state | pause_timer: nil}
  end

  defp pause(state), do: stop_run(state, &Timeline.pause_turn(&1, now_ms()))

  # -- turn state / persistence / broadcast ------------------------------------------

  # The choke point for turn mutations: persistence and broadcast hang off it.
  defp update_current_turn(%{current_turn: nil} = state, _fun), do: broadcast(state)

  defp update_current_turn(state, fun) do
    prev = state.current_turn
    next = fun.(prev)

    %{state | current_turn: next}
    |> persist_turn(prev, next)
    |> broadcast()
  end

  # Two reasons to write a row, neither "every event": the settling write, and a
  # checkpoint while the turn still streams.
  defp persist_turn(%{session_id: nil} = state, _prev, _next), do: state
  defp persist_turn(state, prev, next) when next == prev, do: state

  defp persist_turn(state, _prev, next) do
    cond do
      Timeline.settled_phase?(next.phase) ->
        write_turn(state, next)
        Sessions.touch_session(state.session_id)

        # Reset, so the next turn's checkpoint clock starts from its own first event.
        %{state | checkpointed_at: nil}

      # A turn's first event only starts the clock; `persist_new_turn/2` wrote the row.
      is_nil(state.checkpointed_at) ->
        %{state | checkpointed_at: now_ms()}

      # Bounds what an abrupt node loss (pod eviction, VM kill) takes with it, since
      # nothing settles the turn then. Timed, not per-event: each write serializes the
      # whole timeline.
      now_ms() - state.checkpointed_at >= Config.checkpoint_every_ms() ->
        write_turn(state, next)
        %{state | checkpointed_at: now_ms()}

      true ->
        state
    end
  end

  defp write_turn(state, turn) do
    with {:error, error} <- Sessions.update_turn(state.session_id, turn.id, turn) do
      log_persist_error("update_turn", error)
    end

    :ok
  end

  # Before the run, so a browser closed mid-run still leaves the question behind.
  defp persist_new_turn(%{session_id: session_id} = state, turn) when is_binary(session_id) do
    with {:error, error} <- Sessions.create_turn(session_id, turn, state.model_tier) do
      log_persist_error("create_turn", error)
    end

    :ok
  end

  defp persist_new_turn(_state, _turn), do: :ok

  defp apply_run_level(state, result) do
    %{
      state
      | run_id: result[:run_id] || state.run_id,
        mcp_warning: get_in(result, [:meta, :mcp_warning]) || state.mcp_warning
    }
  end

  defp snapshot(state) do
    %{
      key: state.key,
      session_id: state.session_id,
      thread_id: state.thread_id,
      current_turn: state.current_turn,
      running: state.running,
      mcp_warning: state.mcp_warning,
      next_id: state.next_id
    }
  end

  defp broadcast(state) do
    snap = snapshot(state)
    Enum.each(Map.keys(state.watchers), &send(&1, {:dra_runner, state.key, snap}))
    state
  end

  # -- side-call tasks (fire-and-forget) ----------------------------------------------

  defp check_run_status_async(thread_id, run_id, sink, ref) do
    Task.Supervisor.start_child(Sanbase.TaskSupervisor, fn ->
      send(sink, {:dra_run_status, ref, Client.get_run(thread_id, run_id)})
    end)
  end

  defp poll_state_async(thread_id, sink, ref) do
    Task.Supervisor.start_child(Sanbase.TaskSupervisor, fn ->
      send(sink, {:dra_poll, ref, poll_result(thread_id)})
    end)
  end

  defp poll_result(thread_id) do
    case Client.get_state(thread_id) do
      {:ok, state} -> EventParser.parse_thread_state(state)
      {:error, failure} -> failure
    end
  end

  # No run_id yet (the stream never reported one) — cancel whatever the thread has active.
  defp cancel_run_async(thread_id, run_id) when is_binary(thread_id) do
    Task.Supervisor.start_child(Sanbase.TaskSupervisor, fn ->
      if is_binary(run_id),
        do: Client.cancel_run(thread_id, run_id),
        else: Client.cancel_active_runs(thread_id)
    end)
  end

  defp cancel_run_async(_thread_id, _run_id), do: :ok

  defp log_persist_error(operation, error) do
    Logger.warning("Deep research session persistence failed in #{operation}: #{inspect(error)}")
  end

  defp now_ms(), do: System.system_time(:millisecond)
end
