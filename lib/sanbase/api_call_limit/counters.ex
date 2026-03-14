defmodule Sanbase.ApiCallLimit.Counters do
  @moduledoc """
  Lock-free atomic counters for tracking API usage within a single batch.

  Used by `ApiCallLimit.ETS` to track per-entity (user or IP) API call counts
  and response sizes in memory between Postgres flushes. Each entity gets its
  own counters ref, stored inside the ETS record.

  ## Atomics layout

  Each ref is an `:atomics` array with 4 signed integer slots:

  | Slot | Name             | Purpose                                              |
  |------|------------------|------------------------------------------------------|
  | 1    | `remaining`      | Calls left in the current batch. Starts at `quota`,  |
  |      |                  | decremented by each writer. Can go negative.         |
  | 2    | `byte_size`      | Accumulated response size in bytes for the batch.    |
  | 3    | `flush_lock`     | `0` = free, `1` = flush in progress (CAS gate).     |
  | 4    | `writers`        | Count of processes currently inside `update_usage/3`. |

  ## Writer protocol (`update_usage/3`)

  1. Atomically increment `writers` (register as in-flight).
  2. Read `flush_lock`:
     - If `0`: apply the usage (decrement `remaining`, add `byte_size`),
       return `{:updated, new_remaining}`.
     - If `1`: a flush is in progress — return `:flushing` without
       touching `remaining`/`byte_size`.
  3. Atomically decrement `writers` (unregister), even on exception.

  This guarantees that any write visible to the flusher's snapshot was
  fully applied, and that no write lands on a ref that's mid-snapshot.

  ## Flusher protocol

      :acquired = acquire_flush_lock(ref)
      :drained  = wait_for_writers(ref)
      snapshot  = snapshot(ref, quota)
      # ... persist snapshot to Postgres ...
      # Discard this ref — create a fresh one for the next batch.

  The flusher acquires the lock (CAS `0 → 1`), then spins until all
  in-flight writers have decremented `writers` back to zero. Only then
  is the snapshot guaranteed to be stable.

  If the flush can't complete (e.g. DB failure), call `release_flush_lock/1`
  to reopen the counters for writers instead of discarding the ref.

  ## Lifecycle

  A counters ref is created when the ETS module fetches a new quota batch
  from Postgres (`new/1`). It lives for the duration of that batch — typically
  100–200 API calls or 60 seconds, whichever comes first. After a successful
  flush, the old ref is replaced in ETS with a fresh one and eventually
  garbage-collected.
  """

  @remaining 1
  @byte_size 2
  @flush_lock 3
  @writers 4

  @doc """
  Creates new counters with `quota` remaining calls.

  All other slots (byte_size, flush_lock, writers) start at zero.
  """
  def new(quota) when is_integer(quota) do
    ref = :atomics.new(4, signed: true)
    :atomics.put(ref, @remaining, quota)
    ref
  end

  @doc """
  Returns the current remaining-calls counter.

  Can be negative if multiple writers decremented past zero before a flush.
  """
  def remaining(ref), do: :atomics.get(ref, @remaining)

  @doc """
  Atomically records one request's usage.

  Decrements `remaining` by `count` and increments `byte_size` by `byte_size`.
  Follows the writer protocol: registers as in-flight, checks the flush lock,
  and unregisters on exit.

  Returns:
  - `{:updated, new_remaining}` — usage was applied. If `new_remaining <= 0`,
    the caller should trigger a flush.
  - `:flushing` — a flush is in progress on this ref. The caller should retry
    on a refreshed ETS entry or fall back to a direct DB update.
  """
  def update_usage(ref, count, byte_size) do
    :atomics.add(ref, @writers, 1)

    try do
      case :atomics.get(ref, @flush_lock) do
        0 ->
          new_remaining = :atomics.sub_get(ref, @remaining, count)
          :atomics.add(ref, @byte_size, byte_size)
          {:updated, new_remaining}

        _ ->
          :flushing
      end
    after
      :atomics.sub(ref, @writers, 1)
    end
  end

  @doc """
  Tries to acquire the flush lock via compare-and-swap (`0 → 1`).

  Only one process can hold the lock at a time. The winner proceeds with
  the flush; everyone else gets `:contended` and should back off.

  Returns `:acquired` or `:contended`.
  """
  def acquire_flush_lock(ref) do
    case :atomics.compare_exchange(ref, @flush_lock, 0, 1) do
      :ok -> :acquired
      _ -> :contended
    end
  end

  @doc """
  Releases the flush lock so writers can resume on this ref.

  Call this when a flush fails (e.g. DB error) and you want to keep
  the current ref alive rather than replacing it.
  """
  def release_flush_lock(ref) do
    :atomics.put(ref, @flush_lock, 0)
  end

  @doc """
  Spins until all in-flight writers have completed (`writers == 0`).

  Must be called after `acquire_flush_lock/1` and before `snapshot/2`
  to ensure the snapshot is stable.

  Options:
  - `:max_retries` — maximum spin iterations (default: 200)
  - `:sleep_ms` — milliseconds to sleep between checks (default: 2)

  Returns `:drained` or `:timeout`.
  """
  def wait_for_writers(ref, opts \\ []) do
    max_retries = Keyword.get(opts, :max_retries, 200)
    sleep_ms = Keyword.get(opts, :sleep_ms, 2)
    do_wait(ref, max_retries, sleep_ms)
  end

  @doc """
  Reads the final counter values after writers have drained.

  Returns the total API calls made (`quota - remaining`, floored at 0)
  and the accumulated response byte size. These are the values to persist
  to Postgres.

  Must only be called after `acquire_flush_lock/1` and `wait_for_writers/1`.
  """
  def snapshot(ref, quota) do
    %{
      api_calls_made: max(quota - :atomics.get(ref, @remaining), 0),
      acc_byte_size: max(:atomics.get(ref, @byte_size), 0)
    }
  end

  # -- private --

  defp do_wait(_ref, 0, _sleep_ms), do: :timeout

  defp do_wait(ref, retries, sleep_ms) do
    case :atomics.get(ref, @writers) do
      0 ->
        :drained

      _ ->
        Process.sleep(sleep_ms)
        do_wait(ref, retries - 1, sleep_ms)
    end
  end
end
