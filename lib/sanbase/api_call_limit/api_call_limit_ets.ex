defmodule Sanbase.ApiCallLimit.ETS do
  @moduledoc ~s"""
  In-memory API quota tracking backed by ETS + `ApiCallLimit.Counters`.

  `Sanbase.ApiCallLimit` stores the authoritative counters in Postgres.
  This module keeps short-lived per-entity quota buckets in ETS so requests can
  do lock-free, low-latency usage accounting on each web node and flush usage to
  Postgres in batches.

  ## Storage model

  ETS stores one record per entity (`user_id` or `remote_ip`) with 3 shapes:

  - Active:
    `{entity_key, :active, bucket_ref, quota, base_metadata, refresh_after_datetime}`
  - Unlimited:
    `{entity_key, :infinity}`
  - Cached error:
    `{entity_key, :error, reason, error_map}`

  ## Concurrency

  See `ApiCallLimit.Counters` for the per-bucket writer/flusher protocol.
  This module handles ETS record lifecycle (cold start, replace, error caching)
  and retry/fallback logic.
  """
  use GenServer

  alias Sanbase.ApiCallLimit
  alias Sanbase.ApiCallLimit.Counters
  alias Sanbase.Accounts.User

  require Logger

  @type entity_type :: :remote_ip | :user
  @type remote_ip :: String.t()
  @type entity :: remote_ip | %User{}
  @ets_table :api_call_limit_ets_table

  @max_update_retries 50
  @max_flush_retries 10
  @flush_retry_sleep_ms 5
  @update_retry_sleep_ms 5

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

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
  Returns currently available quota for the entity.

  Served from ETS on the fast path; refreshes from Postgres when the in-memory
  bucket is exhausted or expired. Returns `{:ok, %{quota: :infinity}}` for
  basic auth and unlimited entities.
  """
  @spec get_quota(entity_type, entity, atom()) ::
          {:ok, :infinity} | {:ok, map()} | {:error, map()}
  def get_quota(_type, _entity, :basic), do: {:ok, %{quota: :infinity}}
  def get_quota(:user, %User{} = user, _auth_method), do: do_get_quota(:user, user, user.id)
  def get_quota(:remote_ip, ip, _auth_method), do: do_get_quota(:remote_ip, ip, ip)

  @doc ~s"""
  Records API usage for a user or remote IP.

  Usage is applied to the per-entity Counters atomics counters and eventually
  flushed to Postgres in batches. Under heavy flush contention, retries and
  falls back to a direct DB update to avoid dropping usage.
  """
  def update_usage(_type, :basic, _user_or_remote_ip, _count, _result_byte_size), do: :ok

  def update_usage(:user, _auth_method, %User{} = user, count, result_byte_size),
    do: do_update_usage(:user, user, user.id, count, result_byte_size)

  def update_usage(:remote_ip, _auth_method, remote_ip, count, result_byte_size),
    do: do_update_usage(:remote_ip, remote_ip, remote_ip, count, result_byte_size)

  # ---------------------------------------------------------------------------
  # get_quota dispatch
  # ---------------------------------------------------------------------------

  defp do_get_quota(entity_type, entity, entity_key, retries \\ @max_flush_retries) do
    case :ets.lookup(@ets_table, entity_key) do
      [] ->
        handle_cold_start_get_quota(entity_type, entity, entity_key, retries)

      [{^entity_key, :error, reason, error_map}]
      when reason in [:rate_limited, :response_size_limit_exceeded] ->
        handle_cached_error(entity_type, entity, entity_key, error_map)

      [{^entity_key, :infinity}] ->
        {:ok, %{quota: :infinity}}

      [{^entity_key, :active, ref, quota, base_metadata, refresh_after}] ->
        handle_active_get_quota(
          entity_type,
          entity,
          entity_key,
          ref,
          quota,
          base_metadata,
          refresh_after,
          retries
        )
    end
  end

  defp handle_cold_start_get_quota(entity_type, entity, entity_key, retries) do
    case fetch_and_store_quota(entity_type, entity, entity_key, :insert_new) do
      :already_exists -> do_get_quota(entity_type, entity, entity_key, retries)
      result -> result
    end
  end

  defp handle_cached_error(entity_type, entity, entity_key, error_map) do
    now = DateTime.utc_now()

    if DateTime.compare(now, error_map.retry_again_after) == :lt do
      blocked_for_seconds = DateTime.diff(error_map.blocked_until, now) |> abs()
      {:error, Map.put(error_map, :blocked_for_seconds, blocked_for_seconds)}
    else
      fetch_and_store_quota(entity_type, entity, entity_key)
    end
  end

  defp handle_active_get_quota(
         entity_type,
         entity,
         entity_key,
         ref,
         quota,
         base_metadata,
         refresh_after,
         retries
       ) do
    remaining = Counters.remaining(ref)
    needs_flush = remaining <= 0 or DateTime.compare(DateTime.utc_now(), refresh_after) == :gt

    if needs_flush do
      flush_or_retry_get_quota(
        entity_type,
        entity,
        entity_key,
        ref,
        quota,
        base_metadata,
        retries
      )
    else
      {:ok, compute_quota_data(ref, quota, base_metadata)}
    end
  end

  defp flush_or_retry_get_quota(
         entity_type,
         entity,
         entity_key,
         ref,
         quota,
         base_metadata,
         retries
       ) do
    case try_flush_and_reinit(entity_type, entity, entity_key, ref, quota) do
      {:ok, _} = result ->
        result

      {:error, _} = result ->
        result

      :contended when retries > 0 ->
        # Process.sleep(@flush_retry_sleep_ms + 10 * (@max_flush_retries - retries))
        Process.sleep(@flush_retry_sleep_ms)
        do_get_quota(entity_type, entity, entity_key, retries - 1)

      :contended ->
        # Exhausted retries. Fall back to DB if remaining is exhausted,
        # otherwise return what we have from the current bucket.
        if Counters.remaining(ref) <= 0 do
          ApiCallLimit.get_quota_db(entity_type, entity)
        else
          {:ok, compute_quota_data(ref, quota, base_metadata)}
        end
    end
  end

  # ---------------------------------------------------------------------------
  # update_usage dispatch
  # ---------------------------------------------------------------------------

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
        handle_cold_start_update(
          entity_type,
          entity,
          entity_key,
          count,
          result_byte_size,
          retries
        )

      [{^entity_key, :infinity}] ->
        :ok

      [{^entity_key, :error, reason, _}]
      when reason in [:rate_limited, :response_size_limit_exceeded] ->
        :ok

      [{^entity_key, :active, ref, quota, _base_metadata, _refresh_after}] ->
        handle_active_update(
          entity_type,
          entity,
          entity_key,
          ref,
          quota,
          count,
          result_byte_size,
          retries
        )
    end
  end

  defp handle_cold_start_update(
         entity_type,
         entity,
         entity_key,
         count,
         result_byte_size,
         retries
       ) do
    case fetch_and_store_quota(entity_type, entity, entity_key, :insert_new) do
      :already_exists when retries > 0 ->
        do_update_usage(entity_type, entity, entity_key, count, result_byte_size, retries - 1)

      :already_exists ->
        direct_db_update(entity_type, entity, count, result_byte_size)

      {:ok, %{quota: :infinity}} ->
        :ok

      {:ok, _metadata} ->
        # Entry now exists in ETS. Recurse to apply the usage to it.
        do_update_usage(entity_type, entity, entity_key, count, result_byte_size, retries)

      {:error, _} ->
        :ok
    end
  end

  defp handle_active_update(
         entity_type,
         entity,
         entity_key,
         ref,
         quota,
         count,
         result_byte_size,
         retries
       ) do
    case Counters.update_usage(ref, count, result_byte_size) do
      {:updated, new_remaining} ->
        if new_remaining <= 0 do
          _ = try_flush_and_reinit(entity_type, entity, entity_key, ref, quota)
        end

        if retries < 30 do
          # Will remove after a few weeks of observation
          Logger.warning("""
          Succeeded running Counters.update_usage/3, but had to retry multiple times
          due to ongoing flushing. Retries until success: #{@max_update_retries - retries}
          """)
        end

        :ok

      :flushing when retries > 0 ->
        # When count >= quota and we've already retried a few times, every
        # successful write would immediately exhaust the batch and trigger yet
        # another flush, creating a serial convoy. Go straight to DB.
        already_retried = @max_update_retries - retries

        if count >= quota and already_retried >= 3 do
          direct_db_update(entity_type, entity, count, result_byte_size)
        else
          Process.sleep(@update_retry_sleep_ms)
          do_update_usage(entity_type, entity, entity_key, count, result_byte_size, retries - 1)
        end

      :flushing ->
        Logger.warning("""
        After #{@max_update_retries} retries, Counters.update_usage/3 still gets :flushing
        meaning something might be stuck. Investigate.
        Data: #{entity_type}, #{entity_key}, #{quota}
        """)

        direct_db_update(entity_type, entity, count, result_byte_size)
    end
  end

  defp direct_db_update(entity_type, entity, count, result_byte_size) do
    # Use increment_usage_db (single atomic UPDATE) instead of update_usage_db
    # (SELECT FOR UPDATE + UPDATE). The row lock is held for microseconds
    # instead of milliseconds, so concurrent direct-DB writers don't pile up.
    case ApiCallLimit.increment_usage_db(entity_type, entity, count, result_byte_size) do
      {:ok, :incremented} ->
        :ok

      {:error, reason} ->
        Logger.error(
          "direct_db_update failed for #{entity_type}: #{inspect(reason)}. " <>
            "count=#{count}, result_byte_size=#{result_byte_size}"
        )

        {:error, reason}
    end
  end

  # ---------------------------------------------------------------------------
  # Flush
  # ---------------------------------------------------------------------------

  defp try_flush_and_reinit(entity_type, entity, entity_key, ref, quota) do
    case Counters.acquire_flush_lock(ref) do
      :acquired ->
        do_flush(entity_type, entity, entity_key, ref, quota)

      :contended ->
        :contended
    end
  end

  defp do_flush(entity_type, entity, entity_key, ref, quota) do
    case Counters.wait_for_writers(ref) do
      :drained ->
        %{api_calls_made: calls, acc_byte_size: bytes} = Counters.snapshot(ref, quota)

        case ApiCallLimit.update_usage_db(entity_type, entity, calls, bytes) do
          {:ok, _} ->
            fetch_and_store_quota(entity_type, entity, entity_key, :replace)

          {:error, _} = error ->
            Counters.release_flush_lock(ref)
            error
        end

      :timeout ->
        Counters.release_flush_lock(ref)
        :contended
    end
  end

  # ---------------------------------------------------------------------------
  # Metadata derivation
  # ---------------------------------------------------------------------------

  defp compute_quota_data(ref, quota, base_metadata) do
    remaining_counter = Counters.remaining(ref)
    calls_used = max(quota - remaining_counter, 0)
    base_remaining = base_metadata.api_calls_remaining

    %{
      base_metadata
      | quota: max(remaining_counter, 0),
        api_calls_remaining: %{
          month: max(base_remaining.month - calls_used, 0),
          hour: max(base_remaining.hour - calls_used, 0),
          minute: max(base_remaining.minute - calls_used, 0)
        }
    }
  end

  # ---------------------------------------------------------------------------
  # DB fetch + ETS storage
  # ---------------------------------------------------------------------------

  defp fetch_and_store_quota(entity_type, entity, entity_key, insert_mode \\ :replace) do
    now = DateTime.utc_now()

    case ApiCallLimit.get_quota_db(entity_type, entity) do
      {:ok, %{quota: :infinity} = metadata} ->
        put_and_return(entity_key, {entity_key, :infinity}, insert_mode, {:ok, metadata})

      {:ok, %{quota: quota} = metadata} ->
        ref = Counters.new(quota)
        refresh_after = Timex.shift(now, seconds: 60 - now.second)
        record = {entity_key, :active, ref, quota, metadata, refresh_after}
        put_and_return(entity_key, record, insert_mode, {:ok, metadata})

      {:error, %{reason: reason, blocked_until: _} = error_map}
      when reason in [:rate_limited, :response_size_limit_exceeded] ->
        retry_after =
          Enum.min([error_map.blocked_until, DateTime.add(now, 60, :second)], DateTime)

        error_map = Map.put(error_map, :retry_again_after, retry_after)
        record = {entity_key, :error, reason, error_map}
        put_and_return(entity_key, record, insert_mode, {:error, error_map})
    end
  end

  defp put_and_return(_entity_key, record, :replace, result) do
    :ets.insert(@ets_table, record)
    result
  end

  defp put_and_return(_entity_key, record, :insert_new, result) do
    case :ets.insert_new(@ets_table, record) do
      true -> result
      false -> :already_exists
    end
  end
end
