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

  # Upper bound on the exponential retry backoff for functions that completed
  # with `{:error, _}` (no value delivered). `:nocache` (partial) results are NOT
  # backed off - they re-evaluate on every tick until a clean success.
  @max_retry_backoff_ms :timer.minutes(5)

  # Registered closures are refreshed forever, so keys that are no longer read
  # would keep querying upstreams indefinitely. Once a key has not been read for
  # `@unused_key_pause_ms` its refresh is paused (a later `get` resumes it), and
  # after `@unused_key_drop_ms` it is forgotten entirely (a `get` re-registers it).
  #
  # The pause threshold is intentionally >= the longest refresh cadence a caller
  # uses (the project-metrics resolver refreshes every 30-60 min), so a key that
  # is still in active rotation is never paused between two of its own refreshes.
  @unused_key_pause_ms :timer.hours(1)
  @unused_key_drop_ms :timer.hours(3)

  # Upper bound on new computation tasks started in a single :run tick. Prevents
  # a thundering herd when many keys come due at once (e.g. after a refresh
  # wave); the overflow stays due and runs on subsequent ticks.
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
      # These knobs are configurable so tests can drive behavior quickly instead
      # of depending on the production defaults.
      run_interval: Keyword.get(opts, :run_interval, @run_interval),
      function_runtime_timeout:
        Keyword.get(opts, :function_runtime_timeout, @function_runtime_timeout),
      unused_key_pause_ms: Keyword.get(opts, :unused_key_pause_ms, @unused_key_pause_ms),
      unused_key_drop_ms: Keyword.get(opts, :unused_key_drop_ms, @unused_key_drop_ms),
      max_spawns_per_run: Keyword.get(opts, :max_spawns_per_run, @max_spawns_per_run),
      functions: %{},
      progress: %{},
      # Per-key count of consecutive non-`{:ok, _}` completions. Used to space
      # out retries (exponential backoff) so a persistently failing upstream is
      # not hammered every run interval. Reset to 0 on a clean `{:ok, _}`.
      backoffs: %{},
      # Per-key unix timestamp of the last read. Drives pausing/dropping of keys
      # that are no longer requested.
      last_access: %{},
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
        # Served straight from ETS without touching the GenServer, so tell it
        # this key is still being read (otherwise its refresh would be paused).
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

  # A cast (not a call) so ETS-hit reads never block on the GenServer. The only
  # caller of `get/3` is the GraphQL resolver, which itself sits behind Absinthe
  # request caching, so cast volume here is low; if a high-QPS caller is ever
  # added, move `last_access` to a directly-writable ETS table to keep reads off
  # this process entirely.
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
    # There a few different cases that need to be handled
    # 1. The value is present in the store - serve it
    # 2. Computation is in progress - add the caller to the wait list
    # 3. Computation is not in progress but the function is registered -
    #    re-register the function and add the caller to the wait list
    # 4. None of the above - the key has not been registered
    tuple = %{
      value: Store.get(@store_name, key),
      progress: Map.get(state.progress, key),
      function: Map.get(state.functions, key)
    }

    case tuple do
      %{value: value} when not is_nil(value) ->
        {:reply, value, state}

      %{progress: %Progress{status: :running}} ->
        # If the value is still computing the response will be sent
        # once the value is computed. This will be reached only on the first
        # computation. For subsequent calls with a :running progress, the
        # stored value will be available and the previous case will be matched
        new_state = do_fill_waiting_list(state, key, from, timeout)
        {:noreply, new_state}

      %{progress: %Progress{status: :failed}} ->
        # If progress is :failed it will get started on the next run
        new_state = do_fill_waiting_list(state, key, from, timeout)
        {:noreply, new_state}

      %{function: fun_map} when is_map(fun_map) ->
        # Reaching here is unexpected. If we reached here the function is
        # registered but for some reason it has not started executing because
        # there's no stored value and no progress
        new_state =
          state
          |> do_register_function(fun_map)
          |> do_fill_waiting_list(key, from, timeout)

        {:noreply, new_state}

      _ ->
        {:reply, {:error, :not_registered}, state}
    end
  end

  def handle_call({:register_function, %{key: key} = fun_map}, _from, state) do
    case Map.has_key?(state.functions, key) do
      true ->
        {:reply, {:error, :already_registered}, state}

      false ->
        new_state = do_register_function(state, fun_map)
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

  def handle_info({:store_result, fun_map, data}, state) do
    store_result_handle_info(data, state, fun_map, now_unix())
  end

  def handle_info(:purge_timeouts, state) do
    new_state = do_purge_timeouts(state)
    {:noreply, new_state}
  end

  def handle_info(:log_stats, state) do
    paused =
      Enum.count(state.progress, fn {_key, value} -> match?(%Progress{status: :paused}, value) end)

    Logger.info(
      "[Rehydrating Cache] registered_functions=#{map_size(state.functions)} " <>
        "paused_keys=#{paused} waiting_keys=#{map_size(state.waiting)} " <>
        "backoff_keys=#{map_size(state.backoffs)}"
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
    %{progress: progress, waiting: waiting} = state

    new_state =
      case Enum.find(progress, fn {_k, v} -> match?(%Progress{status: :running, pid: ^pid}, v) end) do
        {k, _v} ->
          new_progress = Map.update!(progress, k, fn _ -> Progress.failed() end)

          # Free any callers parked on this key instead of letting them block
          # until their own timeout. They get an error and can retry.
          new_waiting = pop_and_reply(waiting, k, {:error, :computation_failed})

          %{state | progress: new_progress, waiting: new_waiting}

        nil ->
          state
      end

    {:noreply, new_state}
  end

  def handle_info(msg, state) do
    Logger.error("[Rehydrating Cache] Got unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  # Private functions

  defp do_register_function(state, fun_map) do
    %{key: key} = fun_map

    fun_map =
      fun_map
      |> Map.merge(%{
        registered_at: Timex.now(),
        refresh_count: 0,
        nocache_refresh_count: 0
      })

    %{pid: pid} = run_function(self(), fun_map, state.task_supervisor)
    now_unix = now_unix()
    new_progress = Map.put(state.progress, key, Progress.running(pid, now_unix))
    new_functions = Map.put(state.functions, key, fun_map)
    new_last_access = Map.put(state.last_access, key, now_unix)

    %{state | functions: new_functions, progress: new_progress, last_access: new_last_access}
  end

  defp do_purge_timeouts(state) do
    %{waiting: waiting} = state
    now = Timex.now()

    new_waiting =
      Enum.reduce(waiting, %{}, fn {key, waiting_for_key}, acc ->
        # Remove from the waiting list all timed out records. These are the `call`s
        # that are no longer waiting for response.
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

  # Spawns the computation task and returns the :running progress for the key.
  defp spawn_and_track(state, fun_map) do
    %{task_supervisor: task_supervisor, now_unix: now_unix} = state

    %{pid: pid} = run_function(self(), fun_map, task_supervisor)
    Progress.running(pid, now_unix)
  end

  # Returns `{next_progress_value, spawned?}` for an already in-progress key.
  # A dead or stuck task needs restarting, but that restart must go through the
  # same gating as any other spawn (unused-key pause + per-tick cap) so a wave of
  # simultaneously dying/stuck tasks can't burst past the cap. A stuck task is
  # always killed first, even when the restart itself is deferred or paused, so
  # it can never leak.
  defp handle_in_progress_function_run(
         state,
         key,
         %Progress{status: :running} = progress,
         fun_map,
         spawns
       ) do
    %Progress{pid: pid, started_unix: started_unix} = progress

    cond do
      not Process.alive?(pid) ->
        # Dead but still marked :running (e.g. the :DOWN has not been handled
        # yet). Restart it, subject to gating.
        maybe_spawn(state, key, fun_map, spawns)

      elapsed_ms(started_unix, state.now_unix) > state.function_runtime_timeout ->
        # Alive but taking too long - kill it, then restart subject to gating.
        Process.exit(pid, :kill)
        maybe_spawn(state, key, fun_map, spawns)

      true ->
        # Still running within the runtime budget - keep the progress as is.
        {progress, false}
    end
  end

  # Walk over the functions and re-evaluate the ones that have to be re-evaluated.
  # Each branch computes the next progress *value* for the key and the reduce
  # threads it into the progress accumulator. Threading through the accumulator
  # (rather than rebuilding from `state.progress`) is essential: otherwise, when
  # several keys are due in the same tick, only the last one keeps its
  # `:running` progress and the rest get spawned again on every tick.
  #
  # The reduce also collects keys to forget (unread for too long) and caps how
  # many new tasks are spawned in a single tick.
  defp do_run(state) do
    now_unix = now_unix()
    state = Map.put(state, :now_unix, now_unix)

    {new_progress, drop_keys, _spawns} =
      Enum.reduce(state.functions, {%{}, [], 0}, fn {key, fun_map},
                                                    {progress_acc, drop_acc, spawns} ->
        cond do
          droppable_key?(state, key, now_unix) ->
            {progress_acc, [key | drop_acc], spawns}

          true ->
            {progress_value, spawned?} = next_progress_value(state, key, fun_map, spawns)
            spawns = if spawned?, do: spawns + 1, else: spawns
            {Map.put(progress_acc, key, progress_value), drop_acc, spawns}
        end
      end)

    state = drop_unused_keys(state, drop_keys)
    Process.send_after(self(), :run, state.run_interval)
    %{state | progress: new_progress}
  end

  # Returns `{next_progress_value, spawned?}` for a key. `spawned?` is true only
  # when a fresh computation task was started, so the caller can enforce the
  # per-tick spawn cap.
  defp next_progress_value(state, key, fun_map, spawns) do
    now_unix = state.now_unix

    case Map.get(state.progress, key) do
      %Progress{status: :running} = progress ->
        handle_in_progress_function_run(state, key, progress, fun_map, spawns)

      %Progress{status: :failed} ->
        # Task execution failed, retry (subject to pause/cap).
        maybe_spawn(state, key, fun_map, spawns)

      %Progress{status: :paused} = progress ->
        # Unread key - stays paused until a read resumes it (see
        # put_last_access/2) or it ages out and is dropped.
        {progress, false}

      %Progress{status: :scheduled, run_after_unix: run_after_unix}
      when now_unix >= run_after_unix ->
        # It is time to execute the function again (subject to pause/cap).
        maybe_spawn(state, key, fun_map, spawns)

      %Progress{status: :scheduled} = progress ->
        # It's still not time to reevaluate the function again.
        {progress, false}

      nil ->
        # No recorded progress. Should not happen; run it to be safe.
        maybe_spawn(state, key, fun_map, spawns)
    end
  end

  defp maybe_spawn(state, key, fun_map, spawns) do
    now_unix = state.now_unix

    cond do
      unused_key?(state, key, now_unix) ->
        # Not read recently - pause refreshing. The distinct :paused status (as
        # opposed to a scheduled future timestamp) lets a later read resume the
        # key as immediately due, instead of it waiting out a whole refresh
        # window and serving a stale value in the meantime.
        {Progress.paused(), false}

      spawns >= state.max_spawns_per_run ->
        # Spawn budget for this tick is exhausted; stay due and run on a
        # subsequent tick.
        {Progress.scheduled(now_unix), false}

      true ->
        {spawn_and_track(state, fun_map), true}
    end
  end

  # A key is dropped once it has not been read for `unused_key_drop_ms`, so
  # forgotten keys stop consuming state and refresh cycles. In-progress keys are
  # never dropped mid-flight. A later `get` simply re-registers the closure.
  defp droppable_key?(state, key, now_unix) do
    not match?(%Progress{status: :running}, Map.get(state.progress, key)) and
      unread_ms(state, key, now_unix) > state.unused_key_drop_ms
  end

  defp unused_key?(state, key, now_unix) do
    unread_ms(state, key, now_unix) > state.unused_key_pause_ms
  end

  # Milliseconds since the key was last read.
  defp unread_ms(state, key, now_unix) do
    elapsed_ms(Map.get(state.last_access, key, now_unix), now_unix)
  end

  # The single time source for the cache's second-granularity domain (progress
  # schedules, last_access). Everything that needs "now" as a unix timestamp
  # goes through here so the values are always comparable.
  defp now_unix(), do: System.system_time(:second)

  # The cache's time domain (last_access, progress, ttl, refresh_time_delta) is
  # unix seconds, while the interval module attributes are milliseconds
  # (`:timer.*`). Convert a seconds elapsed span to ms so the two can be compared.
  defp elapsed_ms(from_unix, now_unix), do: (now_unix - from_unix) * 1000

  defp drop_unused_keys(state, []), do: state

  defp drop_unused_keys(state, keys) do
    # Evict the stored values too, not just the metadata. Otherwise `get/3`
    # would keep serving the dropped key's value straight from the store (until
    # its own TTL) and never fall through to :not_registered, so the caller
    # would never re-register the function.
    Enum.each(keys, &Store.delete(@store_name, &1))

    %{
      state
      | functions: Map.drop(state.functions, keys),
        backoffs: Map.drop(state.backoffs, keys),
        last_access: Map.drop(state.last_access, keys)
    }
  end

  defp put_last_access(state, key) do
    now_unix = now_unix()
    state = %{state | last_access: Map.put(state.last_access, key, now_unix)}

    # A read resumes a paused key as immediately due, so its (possibly stale)
    # stored value is replaced on the next tick instead of after a full refresh
    # window.
    case Map.get(state.progress, key) do
      %Progress{status: :paused} ->
        %{state | progress: Map.put(state.progress, key, Progress.scheduled(now_unix))}

      _ ->
        state
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

  # Exponential backoff for the next re-evaluation of a failing/nocache key.
  # The delay doubles with each consecutive failure, starting at one run
  # interval, and is capped at the key's refresh_time_delta so a healthy refresh
  # cadence is never exceeded. Returns `{next_run_unix, new_fail_count}`.
  defp next_run_with_backoff(state, key, now_unix, refresh_time_delta) do
    fail_count = Map.get(state.backoffs, key, 0) + 1
    # Progress timestamps are second-granularity, so the base is at least 1s
    # even when the run interval is sub-second (as in tests).
    base_seconds = max(div(state.run_interval, 1000), 1)
    exponent = min(fail_count - 1, 16)
    # Cap the backoff at @max_retry_backoff_ms (never past the healthy refresh
    # cadence), so a partial/:nocache result is retried within minutes rather
    # than lingering until the next full refresh.
    max_delay_seconds = min(div(@max_retry_backoff_ms, 1000), refresh_time_delta)
    delay = min(round(base_seconds * :math.pow(2, exponent)), max_delay_seconds)

    {now_unix + delay, fail_count}
  end

  # Reply the given value to every caller parked on `key` and return the waiting
  # map with that key removed.
  defp pop_and_reply(waiting, key, value) do
    {reply_to_list, new_waiting} = Map.pop(waiting, key, [])
    reply_to_waiting(reply_to_list, value)
    new_waiting
  end

  # Schedule the next run with backoff and bump the fail counter. Returns the
  # updated `{progress, backoffs}` maps; the two always move together.
  defp progress_and_backoffs_after_failure(state, key, now_unix, refresh_time_delta) do
    {next_run_unix, fail_count} = next_run_with_backoff(state, key, now_unix, refresh_time_delta)

    {Map.put(state.progress, key, Progress.scheduled(next_run_unix)),
     Map.put(state.backoffs, key, fail_count)}
  end

  defp run_function(pid, fun_map, task_supervisor) do
    Task.Supervisor.async_nolink(task_supervisor, fn ->
      %{function: fun} = fun_map
      result = fun.()
      Process.send(pid, {:store_result, fun_map, result}, [])
    end)
  end

  ################################################################################
  ## Split the functionality if the handle_info for the :store_result message
  ## All of the store_result_handle_info/4 function must return valid handle_info
  ## results.
  ##

  defp store_result_handle_info({:error, _} = error, state, fun_map, now_unix) do
    # Errors are not stored. Reply to the parked callers so they fail fast
    # instead of blocking until their own timeout, and back off the retry so a
    # persistently failing upstream is not re-run every tick.
    %{key: key, refresh_time_delta: refresh_time_delta} = fun_map

    new_waiting = pop_and_reply(state.waiting, key, error)

    {new_progress, new_backoffs} =
      progress_and_backoffs_after_failure(state, key, now_unix, refresh_time_delta)

    {:noreply, %{state | progress: new_progress, waiting: new_waiting, backoffs: new_backoffs}}
  end

  defp store_result_handle_info({:nocache, {:ok, _value}} = result, state, fun_map, now_unix) do
    # Store and serve the (possibly partial) result, but respect the :nocache
    # tag fully: re-evaluate on the very next tick, every tick, until a clean
    # {:ok, _} lands. This does not hammer the failing upstream — the recompute
    # is cheap (healthy modules come from the per-module cache and a failing
    # module is short-circuited by its cooldown marker, see
    # Sanbase.Metric.available_metrics_for_selector/2).
    %{key: key, ttl: ttl} = fun_map

    new_waiting = pop_and_reply(state.waiting, key, result)
    new_fun_map = Map.update(fun_map, :nocache_refresh_count, 1, &(&1 + 1))
    new_functions = Map.put(state.functions, key, new_fun_map)

    new_progress = Map.put(state.progress, key, Progress.scheduled(now_unix))
    # A partial result still delivered value - the error backoff starts fresh.
    new_backoffs = Map.delete(state.backoffs, key)

    Store.put(@store_name, key, result, ttl)

    {:noreply,
     %{
       state
       | progress: new_progress,
         waiting: new_waiting,
         functions: new_functions,
         backoffs: new_backoffs
     }}
  end

  defp store_result_handle_info({:ok, _value} = result, state, fun_map, now_unix) do
    # Put the value in the store. Send the result to the waiting callers.
    %{key: key, refresh_time_delta: refresh_time_delta, ttl: ttl} = fun_map

    new_waiting = pop_and_reply(state.waiting, key, result)
    new_fun_map = Map.update(fun_map, :refresh_count, 1, &(&1 + 1))
    new_functions = Map.put(state.functions, key, new_fun_map)
    new_progress = Map.put(state.progress, key, Progress.scheduled(now_unix + refresh_time_delta))
    # Clean success clears the backoff so the next failure starts from scratch.
    new_backoffs = Map.delete(state.backoffs, key)
    Store.put(@store_name, key, result, ttl)

    {:noreply,
     %{
       state
       | progress: new_progress,
         waiting: new_waiting,
         functions: new_functions,
         backoffs: new_backoffs
     }}
  end

  defp store_result_handle_info(_, state, fun_map, now_unix) do
    # The function returned malformed result. Send error to the waiting callers.
    %{key: key, refresh_time_delta: refresh_time_delta, ttl: ttl} = fun_map

    result = {:error, :malformed_result}

    new_waiting = pop_and_reply(state.waiting, key, result)
    new_progress = Map.put(state.progress, key, Progress.scheduled(now_unix + refresh_time_delta))
    Store.put(@store_name, key, result, ttl)

    {:noreply, %{state | progress: new_progress, waiting: new_waiting}}
  end
end
