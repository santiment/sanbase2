defmodule Sanbase.Cache.RehydratingCache do
  @moduledoc ~s"""
  A service that automatically re-runs functions and caches their values at
  intervals smaller than the TTL so the cache never expires but is just renewed.

  This service is useful when heavy queries need to be cached without any waiting
  for recalculation when the cache expires.

  Example usage: cache the function `f` under the key `:key` for up to 1 hour
  but refresh the data every 15 minutes. Under expected conditions the value
  will be refreshed every 15 minutes and the cache will expire only if the
  function fails to evaluate for more than 1 hour.
  """
  use GenServer

  alias Sanbase.Cache.RehydratingCache.Entry
  alias Sanbase.Cache.RehydratingCache.Progress
  alias Sanbase.Cache.RehydratingCache.Store

  require Logger

  @name :__rehydrating_cache__
  @store_name Store.name()

  def name(), do: @name

  @run_interval :timer.seconds(20)
  @purge_timeout_interval :timer.seconds(30)
  @function_runtime_timeout :timer.minutes(5)
  @stats_log_interval :timer.minutes(1)

  # Upper bound on the exponential retry backoff after an `{:error, _}`. `:nocache`
  # (partial) results are NOT backed off - they re-evaluate until a clean success.
  @max_retry_backoff_ms :timer.minutes(5)

  # Registered closures refresh forever, so an unread key would query upstreams for good.
  # Unread for `@unused_key_pause_ms` pauses the refresh (a later `get` resumes it);
  # unread for `@unused_key_drop_ms` forgets it (a `get` re-registers it). The pause
  # threshold is >= the longest refresh cadence a caller uses (30-60 min), so a key in
  # active rotation is never paused between refreshes.
  @unused_key_pause_ms :timer.hours(1)
  @unused_key_drop_ms :timer.hours(3)

  # Cap on new tasks per :run tick, against a thundering herd. The overflow stays due.
  @max_spawns_per_run 250

  defguard are_proper_function_arguments(fun, ttl, refresh_time_delta)
           when is_function(fun, 0) and is_integer(ttl) and ttl > 0 and
                  is_integer(refresh_time_delta) and
                  refresh_time_delta < ttl

  @doc ~s"""
  Start the self rehydrating cache service.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: @name)
  end

  def init(opts) do
    initial_state = %{
      init_time: Timex.now(),
      task_supervisor: Keyword.fetch!(opts, :task_supervisor),
      # Configurable so tests can drive the behavior without the production timings.
      run_interval: Keyword.get(opts, :run_interval, @run_interval),
      function_runtime_timeout:
        Keyword.get(opts, :function_runtime_timeout, @function_runtime_timeout),
      unused_key_pause_ms: Keyword.get(opts, :unused_key_pause_ms, @unused_key_pause_ms),
      unused_key_drop_ms: Keyword.get(opts, :unused_key_drop_ms, @unused_key_drop_ms),
      max_spawns_per_run: Keyword.get(opts, :max_spawns_per_run, @max_spawns_per_run),
      # `key => Entry.t` - all per-key state. See `Sanbase.Cache.RehydratingCache.Entry`.
      entries: %{},
      # `key => [{from, deadline}]` - callers parked on a first computation. Transient,
      # so kept out of the per-key entries.
      waiting: %{}
    }

    Process.send_after(self(), :purge_timeouts, @purge_timeout_interval)
    Process.send_after(self(), :log_stats, @stats_log_interval)
    {:ok, initial_state, {:continue, :initialize}}
  end

  # Public API
  @doc ~s"""
  Register a new cache function record. The arguments are:
    - function: Anonymous 0-arity function that computes the value
    - key: The key the computed value will be associated with
    - ttl: The maximal time the value will be stored for in seconds
    - refresh_time_delta: A number of seconds strictly smaller than ttl. Every
      refresh_time_delta seconds the cache will be recomputed and stored again.
      The count for ttl starts from 0 again when value is recomputed.
  """
  @spec register_function((-> any()), any(), pos_integer(), pos_integer()) ::
          :ok | {:error, :already_registered}
  def register_function(fun, key, ttl, refresh_time_delta, description \\ nil)
      when are_proper_function_arguments(fun, ttl, refresh_time_delta) do
    map = %{
      function: fun,
      key: key,
      ttl: ttl,
      refresh_time_delta: refresh_time_delta,
      description: description
    }

    GenServer.call(@name, {:register_function, map})
  end

  @doc ~s"""
  Get the value associated with key. If the function computing this key is not
  registered return an error straight away. If the function is registered there are
  two cases. The timeout cannot be :infinity.
  1. The first computation of the value is still going. In this case wait at most
  timeout seconds for the result. If the result is computed in that time it is
  returned
  2. The value has been already computed and it's returned straight away. Note that
  if a recomputation is running when get is invoked, the old value is returned.
  """
  @spec get(any(), non_neg_integer(), Keyword.t()) ::
          {:ok, any()} | {:nocache, {:ok, any()}} | {:error, :timeout} | {:error, :not_registered}
  def get(key, timeout \\ 30_000, opts \\ []) when is_integer(timeout) and timeout > 0 do
    case Store.get(@store_name, key) do
      nil ->
        # Miss goes through the GenServer, which records the access itself.
        GenServer.call(@name, {:get, key, timeout}, timeout)
        |> handle_get_response(opts)

      {:ok, value} ->
        # Served from ETS without touching the GenServer, so tell it the key is still
        # read - otherwise its refresh gets paused.
        touch(key)
        {:ok, value}

      {:nocache, {:ok, _value}} = value ->
        touch(key)
        handle_get_response(value, opts)

      data ->
        touch(key)
        data
    end
  catch
    :exit, {:timeout, _} ->
      {:error, :timeout}
  end

  # A cast, not a call, so ETS-hit reads never block on the GenServer. Cast volume is low
  # because `get/3` is only called by the GraphQL resolver, itself behind request caching;
  # for a high-QPS caller, move `last_access` to a writable ETS table.
  defp touch(key), do: GenServer.cast(@name, {:touch, key})

  defp handle_get_response(data, opts) do
    case data do
      {:ok, value} ->
        {:ok, value}

      {:nocache, {:ok, value}} ->
        if Keyword.get(opts, :return_nocache) do
          {:nocache, {:ok, value}}
        else
          {:ok, value}
        end

      {:error, error} ->
        {:error, error}
    end
  end

  # handle_* callbacks

  def handle_continue(:initialize, state) do
    {:noreply, do_run(state)}
  end

  def handle_call({:get, key, timeout}, from, state) do
    state = put_last_access(state, key)
    # 1. Value in the store - serve it
    # 2. Computation running (or failed and retrying) - park the caller
    # 3. Registered but idle, no stored value - start a computation, park the caller
    # 4. None of the above - the key is not registered
    tuple = %{value: Store.get(@store_name, key), entry: Map.get(state.entries, key)}

    case tuple do
      %{value: value} when not is_nil(value) ->
        {:reply, value, state}

      %{entry: %Entry{progress: %Progress{status: status}}} when status in [:running, :failed] ->
        # :running delivers when the task finishes, :failed restarts on the next run.
        new_state = do_fill_waiting_list(state, key, from, timeout)
        {:noreply, new_state}

      %{entry: %Entry{} = entry} ->
        # Idle and nothing stored yet - compute now instead of waiting for the tick.
        new_state =
          state
          |> restart_entry(entry)
          |> do_fill_waiting_list(key, from, timeout)

        {:noreply, new_state}

      _ ->
        {:reply, {:error, :not_registered}, state}
    end
  end

  def handle_call({:register_function, %{key: key} = registration}, _from, state) do
    case Map.has_key?(state.entries, key) do
      true ->
        {:reply, {:error, :already_registered}, state}

      false ->
        new_state = do_register_function(state, registration)
        {:reply, :ok, new_state}
    end
  end

  def handle_cast({:touch, key}, state) do
    {:noreply, put_last_access(state, key)}
  end

  def handle_info(:run, state) do
    new_state = do_run(state)
    {:noreply, new_state}
  end

  def handle_info({:store_result, key, data}, state) do
    case Map.get(state.entries, key) do
      # The entry was dropped while the task was running - discard the result.
      nil -> {:noreply, state}
      entry -> store_result_handle_info(data, state, key, entry, now_unix())
    end
  end

  def handle_info(:purge_timeouts, state) do
    new_state = do_purge_timeouts(state)
    {:noreply, new_state}
  end

  def handle_info(:log_stats, state) do
    paused =
      Enum.count(state.entries, fn {_key, entry} ->
        match?(%Entry{progress: %Progress{status: :paused}}, entry)
      end)

    backoff =
      Enum.count(state.entries, fn {_key, entry} -> entry.backoff_count > 0 end)

    Logger.info(
      "[Rehydrating Cache] registered_functions=#{map_size(state.entries)} " <>
        "paused_keys=#{paused} waiting_keys=#{map_size(state.waiting)} " <>
        "backoff_keys=#{backoff}"
    )

    Process.send_after(self(), :log_stats, @stats_log_interval)
    {:noreply, state}
  end

  def handle_info({ref, _}, state) when is_reference(ref) do
    {:noreply, state}
  end

  def handle_info({:DOWN, _ref, _, _pid, :normal}, state) do
    {:noreply, state}
  end

  def handle_info({:DOWN, _ref, _, pid, _reason}, state) do
    %{entries: entries, waiting: waiting} = state

    running_key =
      Enum.find_value(entries, fn {k, entry} ->
        match?(%Entry{progress: %Progress{status: :running, pid: ^pid}}, entry) && k
      end)

    new_state =
      case running_key do
        nil ->
          state

        key ->
          new_entries = update_progress(entries, key, Progress.failed())

          # Free the parked callers with an error instead of blocking them until their
          # own timeout.
          new_waiting = pop_and_reply(waiting, key, {:error, :computation_failed})

          %{state | entries: new_entries, waiting: new_waiting}
      end

    {:noreply, new_state}
  end

  def handle_info(msg, state) do
    Logger.error("[Rehydrating Cache] Got unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  # Private functions

  # Build an entry from a registration and start its first computation.
  defp do_register_function(state, registration) do
    %{key: key, function: function} = registration
    now_unix = now_unix()
    %{pid: pid} = run_function(self(), key, function, state.task_supervisor)

    entry = %Entry{
      function: function,
      key: key,
      ttl: registration.ttl,
      refresh_time_delta: registration.refresh_time_delta,
      description: registration.description,
      progress: Progress.running(pid, now_unix),
      last_access_unix: now_unix
    }

    %{state | entries: Map.put(state.entries, key, entry)}
  end

  # Compute for an idle entry, refreshing its read time so it is not paused again.
  defp restart_entry(state, entry) do
    now_unix = now_unix()
    %{pid: pid} = run_function(self(), entry.key, entry.function, state.task_supervisor)
    entry = %{entry | progress: Progress.running(pid, now_unix), last_access_unix: now_unix}
    %{state | entries: Map.put(state.entries, entry.key, entry)}
  end

  defp do_purge_timeouts(state) do
    %{waiting: waiting} = state
    now = Timex.now()

    new_waiting =
      Enum.reduce(waiting, %{}, fn {key, waiting_for_key}, acc ->
        # Drop the timed out records - those `call`s no longer wait for a response.
        still_waiting_for_key =
          waiting_for_key
          |> Enum.filter(fn {_from, send_before} ->
            DateTime.compare(send_before, now) != :lt
          end)

        case still_waiting_for_key do
          [] -> acc
          _ -> Map.put(acc, key, still_waiting_for_key)
        end
      end)

    Process.send_after(self(), :purge_timeouts, @purge_timeout_interval)
    %{state | waiting: new_waiting}
  end

  # Spawn a computation and return its :running progress (do_run writes it back).
  defp spawn_and_track(state, entry) do
    %{pid: pid} = run_function(self(), entry.key, entry.function, state.task_supervisor)
    Progress.running(pid, state.now_unix)
  end

  # Update only the progress. No-op if the key is gone.
  defp update_progress(entries, key, progress) do
    case Map.get(entries, key) do
      nil -> entries
      entry -> Map.put(entries, key, %{entry | progress: progress})
    end
  end

  # Re-evaluate the due entries, threading each next progress into a fresh accumulator.
  # Also collects the keys to forget and caps the tasks a single tick spawns.
  defp do_run(state) do
    now_unix = now_unix()
    state = Map.put(state, :now_unix, now_unix)

    {new_entries, drop_keys, _spawns} =
      Enum.reduce(state.entries, {%{}, [], 0}, fn {key, entry}, {entries_acc, drop_acc, spawns} ->
        cond do
          droppable_entry?(entry, now_unix, state.unused_key_drop_ms) ->
            {entries_acc, [key | drop_acc], spawns}

          true ->
            {progress, spawned?} = next_progress(state, entry, spawns)
            spawns = if spawned?, do: spawns + 1, else: spawns
            {Map.put(entries_acc, key, %{entry | progress: progress}), drop_acc, spawns}
        end
      end)

    state = drop_unused_keys(state, drop_keys)
    Process.send_after(self(), :run, state.run_interval)
    %{state | entries: new_entries}
  end

  # `{next_progress, spawned?}`. `spawned?` is true only for a fresh task, so the caller
  # can enforce the per-tick cap.
  defp next_progress(state, entry, spawns) do
    now_unix = state.now_unix

    case entry.progress do
      %Progress{status: :running} = progress ->
        handle_running(state, entry, progress, spawns)

      %Progress{status: :failed} ->
        # Task execution failed, retry (subject to pause/cap).
        maybe_spawn(state, entry, spawns)

      %Progress{status: :paused} = progress ->
        # Unread - paused until a read resumes it or it ages out and is dropped.
        {progress, false}

      %Progress{status: :scheduled, run_after_unix: run_after_unix}
      when now_unix >= run_after_unix ->
        # It is time to execute the function again (subject to pause/cap).
        maybe_spawn(state, entry, spawns)

      %Progress{status: :scheduled} = progress ->
        # It's still not time to reevaluate the function again.
        {progress, false}
    end
  end

  # `{next_progress, spawned?}` for a :running entry. A dead or stuck task restarts under
  # the same gating as any spawn, so a wave of them cannot burst past it. A stuck task is
  # killed even when the restart is deferred, so it never leaks.
  defp handle_running(
         state,
         entry,
         %Progress{pid: pid, started_unix: started_unix} = progress,
         spawns
       ) do
    cond do
      not Process.alive?(pid) ->
        # Dead but still marked :running (the :DOWN is not handled yet) - restart it.
        maybe_spawn(state, entry, spawns)

      elapsed_ms(started_unix, state.now_unix) > state.function_runtime_timeout ->
        # Alive but taking too long - kill it, then restart subject to gating.
        Process.exit(pid, :kill)
        maybe_spawn(state, entry, spawns)

      true ->
        # Still running within the runtime budget - keep the progress as is.
        {progress, false}
    end
  end

  defp maybe_spawn(state, entry, spawns) do
    now_unix = state.now_unix

    cond do
      unused_entry?(entry, now_unix, state.unused_key_pause_ms) ->
        # Not read recently - pause. A distinct :paused status (rather than a future
        # timestamp) lets a later read resume the key as immediately due, instead of
        # serving a stale value for a whole refresh window.
        {Progress.paused(), false}

      spawns >= state.max_spawns_per_run ->
        # Spawn budget for this tick is spent; stay due and run on a later one.
        {Progress.scheduled(now_unix), false}

      true ->
        {spawn_and_track(state, entry), true}
    end
  end

  # Dropped once unread for `unused_key_drop_ms`, never mid-flight. A later `get`
  # re-registers the closure.
  defp droppable_entry?(entry, now_unix, drop_ms) do
    not match?(%Progress{status: :running}, entry.progress) and
      entry_unread_ms(entry, now_unix) > drop_ms
  end

  defp unused_entry?(entry, now_unix, pause_ms) do
    entry_unread_ms(entry, now_unix) > pause_ms
  end

  # Milliseconds since the entry was last read.
  defp entry_unread_ms(entry, now_unix), do: elapsed_ms(entry.last_access_unix, now_unix)

  # The single time source for the second-granularity domain, so every "now" compares.
  defp now_unix(), do: System.system_time(:second)

  # The cache's time domain is unix seconds, the interval attributes are ms.
  defp elapsed_ms(from_unix, now_unix), do: (now_unix - from_unix) * 1000

  defp drop_unused_keys(state, []), do: state

  defp drop_unused_keys(state, keys) do
    # Evict the stored values too: otherwise `get/3` serves the dropped key until its TTL,
    # never falls through to :not_registered, and the caller never re-registers.
    Enum.each(keys, &Store.delete(@store_name, &1))

    %{state | entries: Map.drop(state.entries, keys)}
  end

  # A no-op for keys with no entry (unregistered, or dropped since the read hit the
  # store), so no orphan is created. A read also resumes a paused key as immediately due.
  defp put_last_access(state, key) do
    case Map.get(state.entries, key) do
      nil ->
        state

      entry ->
        now_unix = now_unix()
        entry = %{entry | last_access_unix: now_unix}

        entry =
          case entry.progress do
            %Progress{status: :paused} -> %{entry | progress: Progress.scheduled(now_unix)}
            _ -> entry
          end

        %{state | entries: Map.put(state.entries, key, entry)}
    end
  end

  defp reply_to_waiting([], _), do: :ok

  defp reply_to_waiting(from_list, value) do
    now = Timex.now()

    Enum.each(from_list, fn {from, send_before} ->
      # Do not reply in case of timeout
      case DateTime.compare(send_before, now) do
        :lt -> :ok
        _ -> GenServer.reply(from, value)
      end
    end)
  end

  defp do_fill_waiting_list(state, key, from, timeout) do
    elem = {from, Timex.shift(Timex.now(), milliseconds: timeout)}
    new_waiting = Map.update(state.waiting, key, [elem], fn list -> [elem | list] end)
    %{state | waiting: new_waiting}
  end

  # The delay doubles per consecutive failure from one run interval, capped at
  # @max_retry_backoff_ms and at the entry's refresh_time_delta, so a broken upstream is
  # still retried within minutes.
  defp backoff_progress(entry, now_unix, run_interval) do
    fail_count = entry.backoff_count + 1
    # Progress timestamps are second-granularity, so the base is at least 1s.
    base_seconds = max(div(run_interval, 1000), 1)
    exponent = min(fail_count - 1, 16)

    max_delay_seconds = min(div(@max_retry_backoff_ms, 1000), entry.refresh_time_delta)
    delay = min(round(base_seconds * :math.pow(2, exponent)), max_delay_seconds)

    {Progress.scheduled(now_unix + delay), fail_count}
  end

  # Reply to every caller parked on `key` and drop it from the waiting map.
  defp pop_and_reply(waiting, key, value) do
    {reply_to_list, new_waiting} = Map.pop(waiting, key, [])
    reply_to_waiting(reply_to_list, value)
    new_waiting
  end

  defp run_function(pid, key, fun, task_supervisor) do
    Task.Supervisor.async_nolink(task_supervisor, fn ->
      result = fun.()
      # Report back by key only; the handler reads the rest from the entry.
      Process.send(pid, {:store_result, key, result}, [])
    end)
  end

  ################################################################################
  ## Handle a computation result. Each clause replies to the parked callers and returns
  ## the entry updated for the next run. The entry is always present (a :running key
  ## can't be dropped).

  defp store_result_handle_info({:error, _} = error, state, key, entry, now_unix) do
    # Errors are not stored. Reply so parked callers fail fast, and back off so a broken
    # upstream is not re-run every tick.
    new_waiting = pop_and_reply(state.waiting, key, error)
    {progress, backoff_count} = backoff_progress(entry, now_unix, state.run_interval)
    new_entry = %{entry | progress: progress, backoff_count: backoff_count}

    {:noreply, %{state | entries: Map.put(state.entries, key, new_entry), waiting: new_waiting}}
  end

  defp store_result_handle_info({:nocache, {:ok, _value}} = result, state, key, entry, now_unix) do
    # Store and serve the partial result, but respect the :nocache tag: re-evaluate every
    # tick until a clean {:ok, _} lands. Cheap - healthy modules come from the per-module
    # cache and a failing one is short-circuited by its cooldown marker.
    new_waiting = pop_and_reply(state.waiting, key, result)

    new_entry = %{
      entry
      | progress: Progress.scheduled(now_unix),
        # A partial result still delivered value - the error backoff starts fresh.
        backoff_count: 0
    }

    Store.put(@store_name, key, result, entry.ttl)

    {:noreply, %{state | entries: Map.put(state.entries, key, new_entry), waiting: new_waiting}}
  end

  defp store_result_handle_info({:ok, _value} = result, state, key, entry, now_unix) do
    # Put the value in the store. Send the result to the waiting callers.
    new_waiting = pop_and_reply(state.waiting, key, result)
    next_run_unix = now_unix + entry.refresh_time_delta

    new_entry = %{
      entry
      | progress: Progress.scheduled(next_run_unix),
        # Clean success clears the backoff so the next failure starts from scratch.
        backoff_count: 0
    }

    Store.put(@store_name, key, result, entry.ttl)

    {:noreply, %{state | entries: Map.put(state.entries, key, new_entry), waiting: new_waiting}}
  end

  defp store_result_handle_info(_, state, key, entry, now_unix) do
    # The function returned a malformed result. Send an error to the waiting callers.
    result = {:error, :malformed_result}

    new_waiting = pop_and_reply(state.waiting, key, result)
    next_run_unix = now_unix + entry.refresh_time_delta
    new_entry = %{entry | progress: Progress.scheduled(next_run_unix)}

    Store.put(@store_name, key, result, entry.ttl)

    {:noreply, %{state | entries: Map.put(state.entries, key, new_entry), waiting: new_waiting}}
  end
end
