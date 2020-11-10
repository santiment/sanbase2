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

  def clear_all() do
    @ets_table
    |> :ets.delete_all_objects()
  end

  @doc ~s"""
  Get a quota that represent the number of API calls that can be made and tracked
  in-memory in an ETS table before checking the postgres database again.

  A special case is when the authentication is Basic Authentication. It is used
  exclusievly from internal services and there will be no limit imposed.

  Returns {:ok, infinity}, {:ok, number} or {:error, map}
  """
  @spec get_quota(entity_type, entity, atom()) ::
          {:ok, :infinity} | {:ok, integer()} | {:error, map()}
  def get_quota(_type, _entity, :basic), do: {:ok, :infinity}
  def get_quota(:user, %User{} = user, _auth_method), do: do_get_quota(:user, user, user.id)
  def get_quota(:remote_ip, ip, _auth_method), do: do_get_quota(:remote_ip, ip, ip)

  @doc ~s"""
  Updates the number of api calls made by a user or an ip address. The number of
  API calls is tracked in-memory in an ETS table and after a certain number of
  API calls is made, the number is updated in the centralized database.
  """
  def update_usage(_type, _entity, :basic), do: :ok

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
        with {:ok, quota} <- ApiCallLimit.get_quota_db(entity_type, entity) do
          true = :ets.insert(@ets_table, {entity_key, quota, quota})
          {:ok, quota}
        end

      [{^entity_key, :rate_limited, error_map}] ->
        case DateTime.compare(DateTime.utc_now(), error_map.blocked_until) do
          :lt ->
            {:error, error_map}

          _ ->
            with {:ok, quota} <- ApiCallLimit.get_quota_db(entity_type, entity) do
              true = :ets.insert(@ets_table, {entity_key, quota, quota})
              {:ok, quota}
            end
        end

      [{^entity_key, :infinity, :infinity}] ->
        {:ok, :infinity}

      [{^entity_key, api_calls_left, quota}] when api_calls_left <= 0 ->
        :ok = ApiCallLimit.update_usage_db(entity_type, entity, quota + -api_calls_left)

        with {:ok, quota} <- ApiCallLimit.get_quota_db(entity_type, entity) do
          true = :ets.insert(@ets_table, {entity_key, quota, quota})
          {:ok, quota}
        end

      [{^entity_key, api_calls_left, _}] ->
        {:ok, api_calls_left}
    end
  end

  defp do_update_usage(entity_type, entity, entity_key, count) do
    case :ets.lookup(@ets_table, entity_key) do
      [] ->
        :ok = ApiCallLimit.update_usage_db(entity_type, entity, count)

        get_quota_db_and_update_ets(entity_type, entity, entity_key)

        :ok

      [{^entity_key, :rate_limited, data}] ->
        case DateTime.compare(DateTime.utc_now(), data.retry_again_after) do
          :lt ->
            :ok

          _ ->
            nil
        end

      [{^entity_key, :infinity, :infinity}] ->
        :ok

      [{^entity_key, api_calls_left, quota}] when api_calls_left <= count ->
        :ok = ApiCallLimit.update_usage_db(entity_type, entity, quota + api_calls_left + count)
        get_quota_db_and_update_ets(entity_type, entity, entity_key)

        :ok

      [{^entity_key, api_calls_left, _quota}] ->
        true = :ets.update_element(@ets_table, entity_key, {2, api_calls_left - count})
        :ok
    end
  end

  defp get_quota_db_and_update_ets(entity_type, entity, entity_key) do
    case ApiCallLimit.get_quota_db(entity_type, entity) do
      {:ok, quota} ->
        true = :ets.insert(@ets_table, {entity_key, quota, quota})

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
    end
  end
end
