defmodule Sanbase.ApiCallLimit.ETS do
  use GenServer

  alias Sanbase.ApiCallLimit
  alias Sanbase.Auth.User

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

  @doc ~s"""
  Get a quota that represent the number of API calls that can be made and tracked
  in-memory in an ETS table before checking the postgres database again.

  A special case is when the authentication is Basic Authentication. It is used
  exclusievly from internal services and there will be no limit imposed.
  """
  def get_quota(_type, _entity, :basic),
    do: {:ok, :infinity}

  def get_quota(:user, %User{} = user, _auth_method) do
    do_get_quota(:user, user, user.id)
  end

  def get_quota(:remote_ip, remote_ip, _auth_method) do
    do_get_quota(:remote_ip, remote_ip, remote_ip)
  end

  @doc ~s"""
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
        {:ok, quota} = ApiCallLimit.get_quota_db(entity_type, entity)
        true = :ets.insert(@ets_table, {entity_key, quota, quota})
        {:ok, quota}

      [{^entity_key, :infinity, :infinity}] ->
        {:ok, :infinity}

      [{^entity_key, api_calls_left, quota}] when api_calls_left <= 0 ->
        :ok = ApiCallLimit.update_usage_db(entity_type, entity, quota + -api_calls_left)
        {:ok, quota} = ApiCallLimit.get_quota_db(entity_type, entity)
        true = :ets.insert(@ets_table, {entity_key, quota, quota})

        {:ok, quota}

      [{^entity_key, api_calls_left, _}] ->
        {:ok, api_calls_left}
    end
  end

  defp do_update_usage(entity_type, entity, entity_key, count) do
    case :ets.lookup(@ets_table, entity_key) do
      [] ->
        :ok = ApiCallLimit.update_usage_db(entity_type, entity, count)
        {:ok, quota} = ApiCallLimit.get_quota_db(entity_type, entity)
        true = :ets.insert(@ets_table, {entity_key, quota, quota})
        :ok

      [{^entity_key, :infinity, :infinity}] ->
        :ok

      [{^entity_key, api_calls_left, _quota}] ->
        true = :ets.update_element(@ets_table, entity_key, {2, api_calls_left - count})
        :ok
    end
  end
end
