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

  alias Sanbase.Cache.RehydratingCache.Store

  @name :__rehydrating_cache__
  @store_name Store.name(@name)

  def name(), do: @name

  @run_interval 10_000
  @purge_timeout_interval 30_000

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
      functions: %{},
      progress: %{},
      waiting: %{}
    }

    Process.send_after(self(), :purge_timeouts, @purge_timeout_interval)
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
  @spec register_function((() -> any()), any(), pos_integer(), pos_integer()) ::
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
  @spec get(any(), non_neg_integer()) ::
          {:ok, any()} | {:error, :timeout} | {:error, :not_registered}
  def get(key, timeout \\ 30_000) when is_integer(timeout) and timeout > 0 do
    try do
      case Store.get(@store_name, key) do
        nil ->
          GenServer.call(@name, {:get, key, timeout}, timeout)

        {:ok, value, _datetime_stored_at} ->
          {:ok, value}

        data ->
          data
      end
    catch
      :exit, {:timeout, _} ->
        {:error, :timeout}
    end
  end

  # handle_* callbacks

  def handle_continue(:initialize, state) do
    {:noreply, do_run(state)}
  end

  def handle_call({:get, key, timeout}, from, state) do
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
      %{value: {value, _datetime_stored_at}} ->
        {:reply, value, state}

      %{progress: :in_progress} ->
        # If the value is still computing the response will be sent
        # once the value is computed. This will be reached only on the first
        # computation. For subsequent calls with :in_progress progress, the
        # stored value will be available and the previous case will be matched
        new_state = do_fill_waiting_list(state, key, from, timeout)
        {:noreply, new_state}

      %{function: fun_map} when is_map(fun_map) ->
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

  def handle_info(:run, state) do
    new_state = do_run(state)
    {:noreply, new_state}
  end

  def handle_info({:store_result, fun_map, result}, state) do
    %{progress: progress, waiting: waiting, functions: functions} = state
    %{key: key, refresh_time_delta: refresh_time_delta, ttl: ttl} = fun_map

    now_unix = Timex.now() |> DateTime.to_unix()

    case result do
      {:error, _} ->
        # Can be reevaluated immediately
        new_progress = Map.put(progress, key, now_unix)
        {:noreply, %{state | progress: new_progress}}

      # Store the result but let it be reevaluated immediately on the next run.
      # This is to not calculate a function that always returns :nocache on
      # every run.
      {:nocache, {:ok, value}} ->
        {reply_to_list, new_waiting} = Map.pop(waiting, key, [])
        reply_to_waiting(reply_to_list, {:ok, value})

        new_fun_map = Map.update(fun_map, :nocache_refresh_count, 1, &(&1 + 1))
        new_functions = Map.put(functions, key, new_fun_map)
        new_progress = Map.put(progress, key, now_unix)
        Store.put(@store_name, key, {:ok, value, Timex.now()}, ttl)

        {:noreply,
         %{state | progress: new_progress, waiting: new_waiting, functions: new_functions}}

      # Put the value in the store. Send the result to the waiting callers.
      {:ok, value} ->
        {reply_to_list, new_waiting} = Map.pop(waiting, key, [])
        reply_to_waiting(reply_to_list, {:ok, value})

        new_fun_map = Map.update(fun_map, :refresh_count, 1, &(&1 + 1))
        new_functions = Map.put(functions, key, new_fun_map)
        new_progress = Map.put(progress, key, now_unix + refresh_time_delta)
        Store.put(@store_name, key, {:ok, value, Timex.now()}, ttl)

        {:noreply,
         %{state | progress: new_progress, waiting: new_waiting, functions: new_functions}}

      # The function returned malformed result. Send error to the waiting callers.
      _ ->
        new_progress = Map.put(progress, key, now_unix + refresh_time_delta)
        result = {:error, :malformed_result}
        Store.put(@store_name, key, {result, Timex.now()}, ttl)

        {reply_to_list, new_waiting} = Map.pop(waiting, key, [])
        reply_to_waiting(reply_to_list, result)

        {:noreply, %{state | progress: new_progress, waiting: new_waiting}}
    end
  end

  def handle_info(:purge_timeouts, state) do
    new_state = do_purge_timeouts(state)
    {:noreply, new_state}
  end

  def handle_info({ref, _}, state) when is_reference(ref) do
    {:noreply, state}
  end

  def handle_info({:DOWN, _ref, _, _pid, _reason}, state) do
    {:noreply, state}
  end

  defp do_register_function(state, fun_map) do
    %{key: key} = fun_map

    fun_map =
      fun_map
      |> Map.merge(%{
        registered_at: Timex.now(),
        refresh_count: 0,
        nocache_refresh_count: 0
      })

    _task = run_function(self(), fun_map, state.task_supervisor)

    new_progress = Map.put(state.progress, key, :in_progress)
    new_functions = Map.put(state.functions, key, fun_map)

    %{state | functions: new_functions, progress: new_progress}
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

  defp do_run(state) do
    now_unix = Timex.now() |> DateTime.to_unix()
    %{progress: progress, functions: functions, task_supervisor: task_supervisor} = state

    new_progress =
      Enum.reduce(functions, %{}, fn {key, fun_map}, acc ->
        case Map.get(progress, key, now_unix) do
          run_after_unix when is_integer(run_after_unix) and now_unix >= run_after_unix ->
            _task = run_function(self(), fun_map, task_supervisor)
            Map.put(acc, key, :in_progress)

          run_after_unix ->
            Map.put(acc, key, run_after_unix)
        end
      end)

    Process.send_after(self(), :run, @run_interval)
    %{state | progress: new_progress}
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

  defp run_function(pid, fun_map, task_supervisor) do
    Task.Supervisor.async_nolink(task_supervisor, fn ->
      %{function: fun} = fun_map
      result = fun.()
      Process.send(pid, {:store_result, fun_map, result}, [])
    end)
  end
end
