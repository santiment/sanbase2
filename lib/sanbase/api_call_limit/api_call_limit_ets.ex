defmodule Sanbase.ApiCallLimit.ETS do
  @moduledoc ~s"""
  Track the API Call quotas (get and update) of the user and remote IPs.

  The quota is fetched from the central database and the progress of using it is
  tracked in-memory in an ETS table. When API calls are made, the progress is
  updated in the ETS table until `quota` number of API calls are made. Then
  the API calls count is updated in the central DB and a new quota is fetched.

  Concurrency is handled lock-free using :atomics for per-entity counters.
  Each entity (user or IP) gets an :atomics ref with 4 slots:
    - Slot 1: api_calls_remaining (decremented atomically per request)
    - Slot 2: acc_result_byte_size (incremented atomically per request)
    - Slot 3: flush_lock (CAS gate — 0=free, 1=flushing)
    - Slot 4: writers_inflight (guards flush snapshot correctness)

  The fast path (decrementing remaining, adding byte size) uses atomic operations
  with zero synchronization. The slow path (flushing to DB when quota is exhausted)
  uses compare_exchange as a CAS gate so only one process flushes at a time.

  ETS entry shapes:
    Active:  {entity_key, :active, atomics_ref, quota, base_metadata, refresh_after_datetime}
    No limits: {entity_key, :infinity}
    Error:   {entity_key, :error, reason, error_map}
  """
  use GenServer

  alias Sanbase.ApiCallLimit
  alias Sanbase.Accounts.User

  @type entity_type :: :remote_ip | :user
  @type remote_ip :: String.t()
  @type entity :: remote_ip | %User{}
  @ets_table :api_call_limit_ets_table

  # Atomics slot indices
  @remaining_slot 1
  @byte_size_slot 2
  @flush_lock_slot 3
  @writers_inflight_slot 4

  @max_update_retries 50
  @max_flush_retries 3
  @flush_retry_sleep_ms 5
  @max_wait_for_writers_retries 200
  @wait_for_writers_sleep_ms 1

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @doc ~s"""
  Start the ETS table that holds the in-memory api call limit data.
  Such a table is used on every sanbase-web pod
  """
  @impl true
  def init(_opts) do
    ets_table =
      :ets.new(@ets_table, [
        :set,
        :public,
        :named_table,
        read_concurrency: true,
        write_concurrency: true
      ])

    {:ok, %{ets_table: ets_table}}
  end

  def clear_all(), do: :ets.delete_all_objects(@ets_table)

  def clear_data(:user, %User{id: user_id}), do: :ets.delete(@ets_table, user_id)
  def clear_data(:remote_ip, remote_ip), do: :ets.delete(@ets_table, remote_ip)

  @doc ~s"""
  Get a quota that represent the number of API calls that can be made and tracked
  in-memory in an ETS table before checking the postgres database again.

  A special case is when the authentication is Basic Authentication. It is used
  exclusively from internal services and there will be no limit imposed.
  """
  @spec get_quota(entity_type, entity, atom()) ::
          {:ok, :infinity} | {:ok, map()} | {:error, map()}
  def get_quota(_type, _entity, :basic), do: {:ok, %{quota: :infinity}}
  def get_quota(:user, %User{} = user, _auth_method), do: do_get_quota(:user, user, user.id)
  def get_quota(:remote_ip, ip, _auth_method), do: do_get_quota(:remote_ip, ip, ip)

  @doc ~s"""
  Updates the number of api calls made by a user or an ip address. The number of
  API calls is tracked in-memory in an ETS table and after a certain number of
  API calls is made, the number is updated in the centralized database.
  """
  def update_usage(_type, :basic, _user_or_remote_ip, _count, _result_byte_size), do: :ok

  def update_usage(:user, _auth_method, %User{} = user, count, result_byte_size),
    do: do_update_usage(:user, user, user.id, count, result_byte_size)

  def update_usage(:remote_ip, _auth_method, remote_ip, count, result_byte_size),
    do: do_update_usage(:remote_ip, remote_ip, remote_ip, count, result_byte_size)

  # Private functions

  defp do_get_quota(entity_type, entity, entity_key, retries \\ @max_flush_retries) do
    case :ets.lookup(@ets_table, entity_key) do
      [] ->
        # No data stored yet. Initialize by checking postgres.
        case get_quota_from_db_and_update_ets(entity_type, entity, entity_key, :insert_new) do
          :already_exists -> do_get_quota(entity_type, entity, entity_key, retries)
          result -> result
        end

      [{^entity_key, :error, reason, error_map}]
      when reason in [:rate_limited, :response_size_limit_exceeded] ->
        # Try again after `retry_again_after` datetime in case something changed.
        # This handles cases where the data changed without a plan upgrade, for
        # example changing the `has_limits` in the admin panel manually.
        # User plan upgrades are handled separately by clearing the ETS records.
        now = DateTime.utc_now()

        case DateTime.compare(now, error_map.retry_again_after) do
          :lt ->
            blocked_for_seconds = DateTime.diff(error_map.blocked_until, now) |> abs()
            {:error, Map.put(error_map, :blocked_for_seconds, blocked_for_seconds)}

          _ ->
            get_quota_from_db_and_update_ets(entity_type, entity, entity_key)
        end

      [{^entity_key, :infinity}] ->
        {:ok, %{quota: :infinity}}

      [{^entity_key, :active, ref, quota, base_metadata, refresh_after_datetime}] ->
        remaining = :atomics.get(ref, @remaining_slot)

        cond do
          remaining <= 0 ->
            handle_flush_from_get_quota(
              entity_type,
              entity,
              entity_key,
              ref,
              quota,
              base_metadata,
              retries
            )

          DateTime.compare(DateTime.utc_now(), refresh_after_datetime) == :gt ->
            handle_flush_from_get_quota(
              entity_type,
              entity,
              entity_key,
              ref,
              quota,
              base_metadata,
              retries
            )

          true ->
            {:ok, derive_current_metadata(ref, quota, base_metadata)}
        end
    end
  end

  defp handle_flush_from_get_quota(
         entity_type,
         entity,
         entity_key,
         ref,
         quota,
         base_metadata,
         retries
       ) do
    case try_flush_and_reinit(entity_type, entity, entity_key, ref, quota) do
      {:ok, _metadata} = result ->
        result

      {:error, _} = result ->
        result

      :contended when retries > 0 ->
        Process.sleep(@flush_retry_sleep_ms)
        do_get_quota(entity_type, entity, entity_key, retries - 1)

      :contended ->
        # Exhausted retries. If remaining <= 0, fall back to DB for authoritative answer.
        remaining = :atomics.get(ref, @remaining_slot)

        if remaining <= 0 do
          ApiCallLimit.get_quota_db(entity_type, entity)
        else
          {:ok, derive_current_metadata(ref, quota, base_metadata)}
        end
    end
  end

  defp do_update_usage(
         entity_type,
         entity,
         entity_key,
         count,
         result_byte_size,
         retries \\ @max_update_retries
       ) do
    case :ets.lookup(@ets_table, entity_key) do
      [] ->
        # ETS has no entry (cold start or after ETS was cleared). Refresh from DB and
        # apply only this request's usage in ETS; do not write to the DB. Writing to the
        # DB here would let a late or out-of-order update overwrite the authoritative DB
        # state (e.g. after a reset). The DB is updated only when the in-memory quota is
        # exhausted and we flush via try_flush_and_reinit.
        case get_quota_from_db_and_update_ets(entity_type, entity, entity_key, :insert_new) do
          :already_exists when retries > 0 ->
            do_update_usage(entity_type, entity, entity_key, count, result_byte_size, retries - 1)

          :already_exists ->
            do_direct_db_update(entity_type, entity, count, result_byte_size)

          {:ok, %{quota: :infinity}} ->
            :ok

          {:ok, _metadata} ->
            do_update_usage(entity_type, entity, entity_key, count, result_byte_size, retries)

          {:error, _} ->
            :ok
        end

      [{^entity_key, :infinity}] ->
        :ok

      [{^entity_key, :error, reason, _error_map}]
      when reason in [:rate_limited, :response_size_limit_exceeded] ->
        :ok

      [{^entity_key, :active, ref, quota, _base_metadata, _refresh_after}] ->
        case apply_usage_to_active_ref(ref, count, result_byte_size) do
          {:applied, new_remaining} ->
            if new_remaining <= 0 do
              # Quota exhausted. One process flushes and re-initializes.
              # Others will retry on the refreshed ETS entry.
              _ = try_flush_and_reinit(entity_type, entity, entity_key, ref, quota)
            end

            :ok

          :flushing when retries > 0 ->
            Process.sleep(@flush_retry_sleep_ms)
            do_update_usage(entity_type, entity, entity_key, count, result_byte_size, retries - 1)

          :flushing ->
            # Last-resort fallback so this request's usage is not dropped under
            # prolonged contention/flush.
            do_direct_db_update(entity_type, entity, count, result_byte_size)
        end
    end
  end

  defp apply_usage_to_active_ref(ref, count, result_byte_size) do
    # Reserve a writer slot first. Flusher sets lock=1 then waits for this
    # counter to drain before taking a snapshot.
    :atomics.add(ref, @writers_inflight_slot, 1)

    try do
      case :atomics.get(ref, @flush_lock_slot) do
        0 ->
          new_remaining = :atomics.sub_get(ref, @remaining_slot, count)
          :atomics.add(ref, @byte_size_slot, result_byte_size)
          {:applied, new_remaining}

        _ ->
          :flushing
      end
    after
      :atomics.sub(ref, @writers_inflight_slot, 1)
    end
  end

  defp do_direct_db_update(entity_type, entity, count, result_byte_size) do
    _ = ApiCallLimit.update_usage_db(entity_type, entity, count, result_byte_size)
    :ok
  end

  defp wait_for_writers_to_drain(_ref, 0), do: :timeout

  defp wait_for_writers_to_drain(ref, retries) do
    if :atomics.get(ref, @writers_inflight_slot) == 0 do
      :ok
    else
      Process.sleep(@wait_for_writers_sleep_ms)
      wait_for_writers_to_drain(ref, retries - 1)
    end
  end

  defp try_flush_and_reinit(entity_type, entity, entity_key, ref, quota) do
    case :atomics.compare_exchange(ref, @flush_lock_slot, 0, 1) do
      :ok ->
        case wait_for_writers_to_drain(ref, @max_wait_for_writers_retries) do
          :ok ->
            # Snapshot only after in-flight writers have drained.
            remaining = :atomics.get(ref, @remaining_slot)
            acc_byte_size = :atomics.get(ref, @byte_size_slot)
            api_calls_made = max(quota - remaining, 0)

            case ApiCallLimit.update_usage_db(
                   entity_type,
                   entity,
                   api_calls_made,
                   max(acc_byte_size, 0)
                 ) do
              {:ok, _} ->
                # Replace ETS record with freshly fetched quota/error state.
                get_quota_from_db_and_update_ets(entity_type, entity, entity_key, :replace)

              {:error, _} = error ->
                # DB update failed; reopen this ref so requests can continue and
                # another flush can retry later.
                :atomics.put(ref, @flush_lock_slot, 0)
                error
            end

          :timeout ->
            # Could not get a stable snapshot within the wait budget.
            # Release the flush lock and let future requests retry.
            :atomics.put(ref, @flush_lock_slot, 0)
            :contended
        end

      _current ->
        # Another process is flushing.
        :contended
    end
  end

  defp derive_current_metadata(ref, quota, base_metadata) do
    remaining_counter = :atomics.get(ref, @remaining_slot)
    calls_used = max(quota - remaining_counter, 0)
    remaining = base_metadata.api_calls_remaining

    %{
      base_metadata
      | quota: max(remaining_counter, 0),
        api_calls_remaining: %{
          month: max(remaining.month - calls_used, 0),
          hour: max(remaining.hour - calls_used, 0),
          minute: max(remaining.minute - calls_used, 0)
        }
    }
  end

  defp get_quota_from_db_and_update_ets(entity_type, entity, entity_key, insert_mode \\ :replace) do
    now = DateTime.utc_now()

    case ApiCallLimit.get_quota_db(entity_type, entity) do
      {:ok, %{quota: :infinity} = metadata} ->
        case put_record(entity_key, {entity_key, :infinity}, insert_mode) do
          :ok -> {:ok, metadata}
          :already_exists -> :already_exists
        end

      {:ok, %{quota: quota} = metadata} ->
        ref = :atomics.new(4, signed: true)
        :atomics.put(ref, @remaining_slot, quota)
        :atomics.put(ref, @byte_size_slot, 0)
        :atomics.put(ref, @flush_lock_slot, 0)
        :atomics.put(ref, @writers_inflight_slot, 0)

        refresh_after_datetime = Timex.shift(now, seconds: 60 - now.second)

        case put_record(
               entity_key,
               {entity_key, :active, ref, quota, metadata, refresh_after_datetime},
               insert_mode
             ) do
          :ok -> {:ok, metadata}
          :already_exists -> :already_exists
        end

      {:error, %{reason: reason, blocked_until: _} = error_map}
      when reason in [:rate_limited, :response_size_limit_exceeded] ->
        retry_again_after =
          Enum.min(
            [error_map.blocked_until, DateTime.add(now, 60, :second)],
            DateTime
          )

        error_map = Map.put(error_map, :retry_again_after, retry_again_after)

        case put_record(entity_key, {entity_key, :error, reason, error_map}, insert_mode) do
          :ok -> {:error, error_map}
          :already_exists -> :already_exists
        end
    end
  end

  defp put_record(_entity_key, record, :replace) do
    :ets.insert(@ets_table, record)
    :ok
  end

  defp put_record(_entity_key, record, :insert_new) do
    case :ets.insert_new(@ets_table, record) do
      true -> :ok
      false -> :already_exists
    end
  end
end
