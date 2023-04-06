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

  require Logger

  @name :__rehydrating_cache__
  @store_name Store.name()

  def name(), do: @name

  @run_interval 20_000
  @purge_timeout_interval 30_000
  @function_runtime_timeout 5 * 1000 * 60

  defguard are_proper_function_arguments(fun, ttl, refresh_time_delta)
           when is_function(fun, 0) and is_integer(ttl) and ttl > 0 and
                  is_integer(refresh_time_delta) and
                  refresh_time_delta > 0 and
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
      fails: %{},
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
  @spec register_function(
          (() -> any()),
          any(),
          pos_integer(),
          pos_integer(),
          String.t()
        ) ::
          :ok | {:error, :already_registered}
  def register_function(fun, key, ttl, refresh_time_delta, description \\ "")
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
          {:ok, any()}
          | {:nocache, {:ok, any()}}
          | {:error, :timeout}
          | {:error, :not_registered}
  def get(key, timeout \\ 30_000, opts \\ [])
      when is_integer(timeout) and timeout > 0 do
    case Store.get(@store_name, key) do
      nil ->
        GenServer.call(@name, {:get, key, timeout}, timeout)
        |> handle_get_response(opts)

      {:ok, value} ->
        {:ok, value}

      {:nocache, {:ok, _value}} = value ->
        handle_get_response(value, opts)

      data ->
        data
    end
  catch
    :exit, {:timeout, _} ->
      {:error, :timeout}
  end

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

      %{progress: {:in_progress, _task_pid, _started_time_tuple}} ->
        # If the value is still computing the response will be sent
        # once the value is computed. This will be reached only on the first
        # computation. For subsequent calls with :in_progress progress, the
        # stored value will be available and the previous case will be matched
        new_state = do_fill_waiting_list(state, key, from, timeout)
        {:noreply, new_state}

      %{progress: :failed} ->
        # If progress :failed it will get started on the next run
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

  def handle_info(:run, state) do
    new_state = do_run(state)
    {:noreply, new_state}
  end

  def handle_info({:store_result, fun_map, data}, state) do
    now_unix = Timex.now() |> DateTime.to_unix()

    store_result_handle_info(data, state, fun_map, now_unix)
  end

  def handle_info(:purge_timeouts, state) do
    new_state = do_purge_timeouts(state)
    {:noreply, new_state}
  end

  def handle_info({ref, _}, state) when is_reference(ref) do
    {:noreply, state}
  end

  def handle_info({:DOWN, _ref, _, _pid, :normal}, state) do
    {:noreply, state}
  end

  def handle_info({:DOWN, _ref, _, pid, reason}, state) do
    %{progress: progress, fails: fails} = state

    new_state =
      case Enum.find(progress, fn {_k, v} ->
             match?({:in_progress, ^pid, _}, v)
           end) do
        {k, _v} ->
          new_progress = Map.update!(progress, k, fn _ -> :failed end)

          # Store the number of fails and the last reason for the fail
          new_fails =
            Map.update(fails, k, {1, reason}, fn {count, _last_reason} ->
              {count + 1, reason}
            end)

          %{state | progress: new_progress, fails: new_fails}

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
    now = Timex.now()

    new_progress =
      Map.put(
        state.progress,
        key,
        {:in_progress, pid, {now, DateTime.to_unix(now)}}
      )

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

  defp run_function_get_updated_progress(state, key, fun_map) do
    %{progress: progress, task_supervisor: task_supervisor, now_unix: now_unix} = state

    now_dt = DateTime.from_unix!(now_unix)

    %{pid: pid} = run_function(self(), fun_map, task_supervisor)

    # Put both the datetime and unix timestamp in the progress map. The unix is used
    # in checks and guards as it is plain number comparisons. The DateTime is used
    # when inspecting the state during runtime to debug/observe.
    Map.put(progress, key, {:in_progress, pid, {now_dt, now_unix}})
  end

  defp handle_in_progress_function_run(state, pid, key, fun_map, started_unix) do
    case Process.alive?(pid) do
      false ->
        # If the process is dead but for some reason the progress is not
        # changed to some timestamp or to :failed, we rerun it
        run_function_get_updated_progress(state, key, fun_map)

      true ->
        if state.now_unix - started_unix > @function_runtime_timeout do
          # Process computing the function is alive but it is taking
          # too long, maybe something is stuck. Restart the computation
          Process.exit(pid, :kill)
          run_function_get_updated_progress(state, key, fun_map)
        else
          state.progress
        end
    end
  end

  # Walk over the functions and re-evaluate the ones that have to be re-evaluated
  defp do_run(state) do
    now = Timex.now()
    now_unix = now |> DateTime.to_unix()
    state = Map.put(state, :now_unix, now_unix)

    new_progress =
      Enum.reduce(state.functions, %{}, fn {key, fun_map}, acc ->
        case Map.get(state.progress, key, now_unix) do
          :failed ->
            # Task execution failed, retry immediatelly
            _progress = run_function_get_updated_progress(state, key, fun_map)

          run_after_unix
          when is_integer(run_after_unix) and now_unix >= run_after_unix ->
            # It is time to execute the function again
            _progress = run_function_get_updated_progress(state, key, fun_map)

          {:in_progress, pid, {_started_datetime, started_unix}} ->
            handle_in_progress_function_run(
              state,
              pid,
              key,
              fun_map,
              started_unix
            )

          nil ->
            # No recorded progress. Should not happend.
            _progress = run_function_get_updated_progress(state, key, fun_map)

          run_after_unix
          when is_integer(run_after_unix) and now_unix < run_after_unix ->
            # It's still not time to reevaluate the function again
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

  ################################################################################
  ## Split the functionality if the handle_info for the :store_result message
  ## All of the store_result_handle_info/4 function must return valid handle_info
  ## results.
  ##

  defp store_result_handle_info({:error, _}, state, fun_map, now_unix) do
    # Can be reevaluated immediately
    new_progress = Map.put(state.progress, fun_map.key, now_unix)
    {:noreply, %{state | progress: new_progress}}
  end

  defp store_result_handle_info(
         {:nocache, {:ok, _value}} = result,
         state,
         fun_map,
         now_unix
       ) do
    # Store the result but let it be reevaluated immediately on the next run.
    # This is to not calculate a function that always returns :nocache on
    # every run.

    %{progress: progress, waiting: waiting, functions: functions} = state
    %{key: key, ttl: ttl} = fun_map

    {reply_to_list, new_waiting} = Map.pop(waiting, key, [])
    reply_to_waiting(reply_to_list, result)

    new_fun_map = Map.update(fun_map, :nocache_refresh_count, 1, &(&1 + 1))
    new_functions = Map.put(functions, key, new_fun_map)
    new_progress = Map.put(progress, key, now_unix)
    Store.put(@store_name, key, result, ttl)

    {:noreply,
     %{
       state
       | progress: new_progress,
         waiting: new_waiting,
         functions: new_functions
     }}
  end

  defp store_result_handle_info(
         {:ok, _value} = result,
         state,
         fun_map,
         now_unix
       ) do
    # Put the value in the store. Send the result to the waiting callers.
    %{progress: progress, waiting: waiting, functions: functions} = state
    %{key: key, refresh_time_delta: refresh_time_delta, ttl: ttl} = fun_map

    {reply_to_list, new_waiting} = Map.pop(waiting, key, [])
    reply_to_waiting(reply_to_list, result)

    new_fun_map = Map.update(fun_map, :refresh_count, 1, &(&1 + 1))
    new_functions = Map.put(functions, key, new_fun_map)
    new_progress = Map.put(progress, key, now_unix + refresh_time_delta)
    Store.put(@store_name, key, result, ttl)

    {:noreply,
     %{
       state
       | progress: new_progress,
         waiting: new_waiting,
         functions: new_functions
     }}
  end

  defp store_result_handle_info(_, state, fun_map, now_unix) do
    # The function returned malformed result. Send error to the waiting callers.
    %{progress: progress, waiting: waiting} = state
    %{key: key, refresh_time_delta: refresh_time_delta, ttl: ttl} = fun_map

    result = {:error, :malformed_result}

    {reply_to_list, new_waiting} = Map.pop(waiting, key, [])
    reply_to_waiting(reply_to_list, result)

    new_progress = Map.put(progress, key, now_unix + refresh_time_delta)
    Store.put(@store_name, key, {:error, :malformed_result}, ttl)

    {:noreply, %{state | progress: new_progress, waiting: new_waiting}}
  end
end
