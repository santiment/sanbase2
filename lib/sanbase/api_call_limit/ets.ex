defmodule Sanbase.ApiCallLimit.ETS do
  @moduledoc ~s"""
  Track the API Call quotas (get and update) of the user and remote IPs.

  The quota is fetched from the central database and the progress of using it is
  tracked in-memory in an ETS table. When API calls are made, the progress is
  updated in the ETS table until `quota` number of API calls are made. Then
  the API calls count is updated in the central DB and a new quota is fetched.
  """
  use GenServer

  alias Sanbase.ApiCallLimit
  alias Sanbase.Auth.User

  @type entity_type :: :remote_ip | :user
  @type remote_ip :: String.t()
  @type entity :: remote_ip | %User{}
  @ets_table :api_call_limit_ets_table

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
  Get a quota that represent the number of API calls that can be made and tracked
  in-memory in an ETS table before checking the postgres database again.

  A special case is when the authentication is Basic Authentication. It is used
  exclusievly from internal services and there will be no limit imposed.
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
  def update_usage(_type, _entity, _count, :basic), do: :ok

  def update_usage(:user, %User{} = user, count, _auth_method) do
    do_update_usage(:user, user, user.id, count)
  end

  def update_usage(:remote_ip, remote_ip, count, _auth_method) do
    do_update_usage(:remote_ip, remote_ip, remote_ip, count)
  end

  # Private functions

  defp do_get_quota(entity_type, entity, entity_key) do
    case :ets.lookup(@ets_table, entity_key) do
      [] ->
        get_quota_db_and_update_ets(entity_type, entity, entity_key)

      [{^entity_key, :rate_limited, error_map}] ->
        case DateTime.compare(DateTime.utc_now(), error_map.blocked_until) do
          :lt -> {:error, error_map}
          _ -> get_quota_db_and_update_ets(entity_type, entity, entity_key)
        end

      [{^entity_key, :infinity, :infinity, metadata}] ->
        {:ok, %{metadata | quota: :infinity}}

      [{^entity_key, api_calls_remaining, quota}] when api_calls_remaining <= 0 ->
        {:ok, _} = ApiCallLimit.update_usage_db(entity_type, entity, quota + -api_calls_remaining)
        get_quota_db_and_update_ets(entity_type, entity, entity_key)

      [{^entity_key, api_calls_remaining, _quota, metadata}] ->
        {:ok, %{metadata | quota: api_calls_remaining}}
    end
  end

  defp do_update_usage(entity_type, entity, entity_key, count) do
    case :ets.lookup(@ets_table, entity_key) do
      [] ->
        {:ok, _} = ApiCallLimit.update_usage_db(entity_type, entity, count)

        get_quota_db_and_update_ets(entity_type, entity, entity_key)

        :ok

      [{^entity_key, :infinity, :infinity, _metadata}] ->
        :ok

      [{^entity_key, api_calls_remaining, quota, _metadata}] when api_calls_remaining <= count ->
        # If 2+ processes execute :ets.lookup/2 at the same time with the same key
        # it could happen that both processes enter this path. This will lead to
        # updating the DB more than once, thus leading to storing more api calls
        # than the user actually made.
        # This issue is not neatly solved by using a mutex so the read/writes
        # happen sequentially. A better solution would be sought that uses
        # techniques similar to CAS operation.

        lock = Mutex.await(Sanbase.ApiCallLimitMutex, entity_key, 5_000)

        # Do another lookup do re-fetch the data in case we waited for the
        # mutex while some other process was doing work here.
        [{^entity_key, api_calls_remaining, quota, _metadata}] =
          :ets.lookup(@ets_table, entity_key)

        if api_calls_remaining <= count do
          {:ok, _} =
            ApiCallLimit.update_usage_db(
              entity_type,
              entity,
              quota - api_calls_remaining + count
            )

          get_quota_db_and_update_ets(entity_type, entity, entity_key)
        else
          true = do_upate_ets_usage(entity_key, api_calls_remaining - count)
        end

        Mutex.release(Sanbase.ApiCallLimitMutex, lock)
        :ok

      [{^entity_key, api_calls_remaining, _quota, _metadata}] ->
        true = do_upate_ets_usage(entity_key, api_calls_remaining - count)
        :ok
    end
  end

  defp do_upate_ets_usage(entity_key, value) do
    :ets.update_element(@ets_table, entity_key, {2, value})
  end

  defp get_quota_db_and_update_ets(entity_type, entity, entity_key) do
    case ApiCallLimit.get_quota_db(entity_type, entity) do
      {:ok, %{quota: quota} = metadata} ->
        true = :ets.insert(@ets_table, {entity_key, quota, quota, metadata})
        {:ok, metadata}

      {:error, %{} = error_map} ->
        retry_again_after =
          Enum.min(
            [
              error_map.blocked_until,
              DateTime.add(DateTime.utc_now(), 60, :second)
            ],
            DateTime
          )

        error_map = Map.put(error_map, :retry_again_after, retry_again_after)

        true = :ets.insert(@ets_table, {entity_key, :rate_limited, error_map})

        {:error, error_map}
    end
  end
end
