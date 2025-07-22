defmodule Sanbase.ApiCallLimit.CollectorGenServer do
  @moduledoc ~s"""
  Track the API Call quotas (get and update) of the user and remote IPs.

  The quota is fetched from the central database and the progress of using it is
  tracked in-memory in the GenServer state. When API calls are made, the progress is
  updated in the state until `quota` number of API calls are made. Then
  the API calls count is updated in the central DB and a new quota is fetched.
  """
  use GenServer

  alias Sanbase.ApiCallLimit

  @type auth_method :: :jwt | :apikey | :basic
  @type entity_type :: :remote_ip | :user
  @type user_id :: non_neg_integer()
  @type remote_ip :: String.t()
  @type entity_key :: remote_ip | user_id
  @type entity :: remote_ip | user_id

  def start_link(args) do
    GenServer.start_link(__MODULE__, args)
  end

  def init(_args) do
    {:ok, _initial_state = %{}}
  end

  def clear_all(server), do: GenServer.call(server, :clear_all)

  def clear_data(server, msg),
    do: GenServer.call(server, {:clear_data, msg})

  # In test environment we use call to make it synchronous. Otherwise in tests we need
  # to sleep for some time before checking the result
  case Application.compile_env(:sanbase, :env) do
    :test -> def update_usage(server, msg), do: GenServer.call(server, {:update_usage, msg})
    _env -> def update_usage(server, msg), do: GenServer.cast(server, {:update_usage, msg})
  end

  def get_quota(server, msg) do
    GenServer.call(server, {:get_quota, msg})
  end

  def handle_cast(
        {:update_usage, {entity_type, auth_method, entity_key, count, result_byte_size}},
        state
      ) do
    new_state =
      do_update_usage(state, entity_type, auth_method, entity_key, count, result_byte_size)

    {:noreply, new_state}
  end

  def handle_call(
        {:update_usage, {entity_type, auth_method, entity_key, count, result_byte_size}},
        _from,
        state
      ) do
    new_state =
      do_update_usage(state, entity_type, auth_method, entity_key, count, result_byte_size)

    {:reply, :ok, new_state}
  end

  def handle_call({:get_quota, {entity_type, entity_key, auth_method}}, _from, state) do
    {result, new_state} =
      do_get_quota(state, entity_type, entity_key, auth_method)

    {:reply, result, new_state}
  end

  def handle_call(:clear_all, _from, _state) do
    {:reply, :ok, %{}}
  end

  def handle_call({:clear_data, {:user, entity_key}}, _from, state) do
    new_state =
      Map.delete(state, entity_key)

    {:reply, :ok, new_state}
  end

  # Private functions

  defp do_get_quota(state, _type, _entity_key, :basic),
    do: {{:ok, %{quota: :infinity}}, state}

  defp do_get_quota(state, :user, user_id, _auth_method) when is_integer(user_id),
    do: do_get_quota_impl(state, :user, user_id)

  defp do_get_quota(state, :remote_ip, ip, _auth_method),
    do: do_get_quota_impl(state, :remote_ip, ip)

  # Basic auth does not have a quota, so it is not stored in the state
  defp do_update_usage(state, _type, :basic, _user_id_or_remote_ip, _count, _result_byte_size),
    do: state

  defp do_update_usage(state, :user, _auth_method, user_id, count, result_byte_size)
       when is_integer(user_id) do
    do_update_usage_impl(state, :user, user_id, count, result_byte_size)
  end

  defp do_update_usage(state, :remote_ip, _auth_method, remote_ip, count, result_byte_size) do
    do_update_usage_impl(state, :remote_ip, remote_ip, count, result_byte_size)
  end

  defp do_get_quota_impl(state, entity_type, entity_key) do
    case Map.get(state, entity_key) do
      nil ->
        # No data stored yet. Initialize by checking the postgres
        get_quota_from_db_and_update_state(state, entity_type, entity_key)

      {reason, error_map} when reason in [:rate_limited, :response_size_limit_exceeded] ->
        # Try again after `retry_again_after` datetime in case something changed.
        now = DateTime.utc_now()

        case DateTime.compare(now, error_map.retry_again_after) do
          :lt ->
            # Update the `blocked_for_seconds` field in order to properly return
            # the report the time left until unblocked
            blocked_for_seconds = DateTime.diff(error_map.blocked_until, now) |> abs()
            error_map = Map.put(error_map, :blocked_for_seconds, blocked_for_seconds)

            {{:error, error_map}, state}

          _ ->
            # It's time to try again, the rate limited period is over
            get_quota_from_db_and_update_state(state, entity_type, entity_key)
        end

      {_quota = :infinity, _remaining, _result_size, metadata, _refresh_after_datetime} ->
        # The entity does not have rate limits applied
        {{:ok, %{metadata | quota: :infinity}}, state}

      {quota, api_calls_remaining, acc_result_byte_size, _metadata, _refresh_after_datetime}
      when api_calls_remaining <= 0 ->
        # The in-memory quota has been exhausted. The api calls made are
        # recorded in postgres and a new quota is obtained. api_calls_remaing
        # is subtracted as it's negative and
        api_calls_made = quota - api_calls_remaining

        update_usage_get_quota_from_db_and_update_state(
          state,
          entity_type,
          entity_key,
          api_calls_made,
          acc_result_byte_size
        )

      {quota, api_calls_remaining, acc_result_byte_size, metadata, refresh_after_datetime} ->
        # The in-memory quota is not exhausted.
        case DateTime.compare(DateTime.utc_now(), refresh_after_datetime) do
          :gt ->
            api_calls_made = quota - api_calls_remaining

            update_usage_get_quota_from_db_and_update_state(
              state,
              entity_type,
              entity_key,
              api_calls_made,
              acc_result_byte_size
            )

          _ ->
            {{:ok, %{metadata | quota: api_calls_remaining}}, state}
        end
    end
  end

  defp do_update_usage_impl(state, entity_type, entity_key, count, result_byte_size) do
    case Map.get(state, entity_key) do
      nil ->
        {_, new_state} =
          update_usage_get_quota_from_db_and_update_state(
            state,
            entity_type,
            entity_key,
            count,
            result_byte_size
          )

        new_state

      {:infinity, :infinity, _result_size, _metadata, _refresh_after_datetime} ->
        state

      {reason, _error_map}
      when reason in [:rate_limited, :response_size_limit_exceeded] ->
        state

      {quota, api_calls_remaining, acc_result_byte_size, _metadata, _refresh_after_datetime}
      when api_calls_remaining <= count ->
        # The remaining calls in the quota are less than the number of calls made now.
        # Update the central DB, get a new quota and put in state.

        # This is the total amount of calls by which the central DB counter will be
        # updated. This value is equal or greater than the aquired quota.
        api_calls_made = quota - api_calls_remaining + count

        {_, new_state} =
          update_usage_get_quota_from_db_and_update_state(
            state,
            entity_type,
            entity_key,
            api_calls_made,
            acc_result_byte_size + result_byte_size
          )

        new_state

      {_quota, api_calls_remaining, _acc_result_byte_size, metadata, _refresh_after_datetime} ->
        # Update usage in state
        do_update_state_usage(
          state,
          entity_key,
          api_calls_remaining,
          count,
          result_byte_size,
          metadata
        )
    end
  end

  defp do_update_state_usage(
         state,
         entity_key,
         api_calls_remaining,
         count,
         result_byte_size,
         metadata
       ) do
    remaining = metadata.api_calls_remaining

    # This metadata is used for the HTTP headers only. The values here
    # represent how many API calls are left for the current minute/hour/month.
    # If the value is negative, it is increased to 0, which is the correct
    # way to show that the limit is exhausted.
    metadata =
      Map.put(metadata, :api_calls_remaining, %{
        month: Enum.max([remaining.month - count, 0]),
        hour: Enum.max([remaining.hour - count, 0]),
        minute: Enum.max([remaining.minute - count, 0])
      })

    {quota, _old_api_calls_remaining, acc_result_byte_size, _old_metadata, refresh_after_datetime} =
      Map.get(state, entity_key)

    new_entry = {
      quota,
      api_calls_remaining - count,
      acc_result_byte_size + result_byte_size,
      metadata,
      refresh_after_datetime
    }

    Map.put(state, entity_key, new_entry)
  end

  defp update_usage_get_quota_from_db_and_update_state(
         state,
         entity_type,
         entity_key,
         count,
         result_byte_size
       ) do
    {:ok, _} =
      ApiCallLimit.update_usage_db(
        entity_type,
        entity_key,
        count,
        result_byte_size
      )

    get_quota_from_db_and_update_state(state, entity_type, entity_key)
  end

  defp get_quota_from_db_and_update_state(state, entity_type, entity_key) do
    now = DateTime.utc_now()

    case ApiCallLimit.get_quota_db(entity_type, entity_key) do
      {:ok, %{quota: quota} = metadata} ->
        refresh_after_datetime = Timex.shift(now, seconds: 60 - now.second)

        entry =
          {quota, _api_calls_remaining = quota, _acc_result_byte_size = 0, metadata,
           refresh_after_datetime}

        new_state = Map.put(state, entity_key, entry)

        {{:ok, metadata}, new_state}

      {:error, %{reason: reason, blocked_until: _} = error_map}
      when reason in [:rate_limited, :response_size_limit_exceeded] ->
        # Try again after `retry_again_after` datetime in case something changed.
        # This handles cases where the data changed without a plan upgrade, for
        # example changing the `has_limits` in the admin panel manually.
        # User plan upgrades are handled separately by clearing the ETS records
        # for the user.
        retry_again_after =
          Enum.min(
            [error_map.blocked_until, DateTime.add(now, 60, :second)],
            DateTime
          )

        error_map = Map.put(error_map, :retry_again_after, retry_again_after)

        entry = {reason, error_map}
        new_state = Map.put(state, entity_key, entry)

        {{:error, error_map}, new_state}
    end
  end
end
