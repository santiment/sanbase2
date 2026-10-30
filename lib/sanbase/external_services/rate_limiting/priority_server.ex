defmodule Sanbase.ExternalServices.RateLimiting.PriorityServer do
  @moduledoc ~s"""
  A rate limiter that serves the waiting callers by priority.

  Callers block in `wait/2` until they are allowed to make a request. When a
  request slot becomes available it is given to the waiter with the highest
  priority (:high > :normal > :low), FIFO within the same priority. To keep
  the :normal traffic from being starved by a stream of :high requests, at
  least one of every `:normal_every` grants goes to a :normal waiter, if there
  is one.

  Options:
    - :scale - the time window in milliseconds
    - :limit - the max number of requests allowed in the time window
    - :time_between_requests - the minimum time in ms between two grants
    - :normal_every - see above. Defaults to 5, so :normal gets at least 20%
    - :bypass - grant every request immediately (used in tests)
  """
  use GenServer, restart: :permanent, shutdown: 5_000

  require Logger

  @priorities [:high, :normal, :low]

  @type priority :: :high | :normal | :low

  def child_spec(name, options \\ []) do
    %{
      id: name,
      start: {__MODULE__, :start_link, [Keyword.put(options, :name, name)]}
    }
  end

  def start_link(options) do
    GenServer.start_link(__MODULE__, options, name: Keyword.fetch!(options, :name))
  end

  def priorities(), do: @priorities

  @doc ~s"""
  Block until a request with the given priority is allowed.
  """
  @spec wait(GenServer.server(), priority()) :: :ok
  def wait(name, priority \\ :normal) when priority in @priorities do
    GenServer.call(name, {:wait, priority}, :infinity)
  end

  @doc ~s"""
  Do not grant any requests until `datetime`. Used when the API responds with
  429 and a `retry-after` header. Returns immediately, the waiting is done in
  the next `wait/2` call.
  """
  @spec wait_until(GenServer.server(), DateTime.t()) :: :ok
  def wait_until(name, %DateTime{} = datetime) do
    GenServer.call(name, {:wait_until, datetime})
  end

  @impl true
  def init(options) do
    config = Application.get_env(:sanbase, __MODULE__, [])

    state = %{
      bucket: Keyword.fetch!(options, :name),
      scale: Keyword.get(options, :scale, 1000),
      limit: Keyword.get(options, :limit, 5),
      time_between_requests: Keyword.get(options, :time_between_requests, 0),
      normal_every: Keyword.get(options, :normal_every, 5),
      bypass: Keyword.get(options, :bypass, Keyword.get(config, :bypass, false)),
      queues: Map.new(@priorities, &{&1, :queue.new()}),
      grants_since_normal: 0,
      blocked_until: nil,
      timer: nil
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:wait, _priority}, _from, %{bypass: true} = state) do
    {:reply, :ok, state}
  end

  def handle_call({:wait, priority}, from, state) do
    state =
      state
      |> update_in([:queues, priority], &:queue.in(from, &1))
      |> schedule_tick(0)

    {:noreply, state}
  end

  def handle_call({:wait_until, datetime}, _from, state) do
    # Add 1 second as the retry-after header has a seconds precision
    wait_ms = max(DateTime.diff(datetime, DateTime.utc_now(), :millisecond), 0) + 1000
    blocked_until = now_ms() + wait_ms

    Logger.info(
      "[PriorityRateLimiter] #{state.bucket} is blocked for #{wait_ms}ms by a retry-after header"
    )

    # The monotonic time can be negative, so nil is not replaced by 0
    blocked_until =
      if state.blocked_until, do: max(state.blocked_until, blocked_until), else: blocked_until

    {:reply, :ok, %{state | blocked_until: blocked_until}}
  end

  @impl true
  def handle_info(:tick, state) do
    state = %{state | timer: nil}
    now = now_ms()

    cond do
      state.blocked_until != nil and state.blocked_until > now ->
        {:noreply, schedule_tick(state, state.blocked_until - now)}

      true ->
        {:noreply, grant_next(state)}
    end
  end

  # Private functions

  defp grant_next(state) do
    case pop_next(state) do
      {:empty, state} ->
        state

      {priority, from, state} ->
        case Sanbase.RateLimit.hit(state.bucket, state.scale, state.limit) do
          {:allow, _count} ->
            GenServer.reply(from, :ok)

            state
            |> count_grant(priority)
            |> schedule_tick(state.time_between_requests)

          {:deny, wait_ms} ->
            # Put the waiter back in the front of its queue
            state
            |> update_in([:queues, priority], &:queue.in_r(from, &1))
            |> schedule_tick(max(wait_ms, 1))
        end
    end
  end

  # Returns the next waiter that is still alive, so a dead process does not
  # waste a request slot. The dead waiters are dropped from the queues.
  defp pop_next(state) do
    popped =
      Enum.find_value(priority_order(state), fn priority ->
        case :queue.out(state.queues[priority]) do
          {{:value, from}, queue} ->
            {priority, from, put_in(state, [:queues, priority], queue)}

          {:empty, _} ->
            nil
        end
      end)

    case popped do
      nil ->
        {:empty, state}

      {priority, {pid, _} = from, state} ->
        if Process.alive?(pid), do: {priority, from, state}, else: pop_next(state)
    end
  end

  defp priority_order(state) do
    normal_waiting? = not :queue.is_empty(state.queues.normal)

    if normal_waiting? and state.grants_since_normal >= state.normal_every - 1,
      do: [:normal, :high, :low],
      else: @priorities
  end

  defp count_grant(state, :normal), do: %{state | grants_since_normal: 0}
  defp count_grant(state, _), do: %{state | grants_since_normal: state.grants_since_normal + 1}

  defp schedule_tick(%{timer: nil} = state, after_ms) do
    %{state | timer: Process.send_after(self(), :tick, after_ms)}
  end

  defp schedule_tick(state, _after_ms), do: state

  defp now_ms(), do: System.monotonic_time(:millisecond)
end
