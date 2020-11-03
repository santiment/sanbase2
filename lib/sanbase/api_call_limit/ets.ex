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

  def get_quota(:user, %User{id: user_id} = user, _auth_method) do
    case :ets.lookup(@ets_table, user_id) do
      [] ->
        {:ok, quota} = ApiCallLimit.get_quota_db(:user, user)
        true = :ets.insert(@ets_table, {user_id, quota, quota})
        {:ok, quota}

      [{^user_id, :infinity, :infinity}] ->
        {:ok, :infinity}

      [{^user_id, api_calls_left, quota}] when api_calls_left <= 0 ->
        # If one graphql request contains multiple batched queries the
        # api_calls_left value can become negative
        :ok = ApiCallLimit.update_usage_db(:user, user, quota + -api_calls_left)
        {:ok, quota} = ApiCallLimit.get_quota_db(:user, user)
        true = :ets.insert(@ets_table, {user_id, quota, quota})

        {:ok, quota}

      [{^user_id, api_calls_left, _}] ->
        {:ok, api_calls_left}
    end
  end

  def get_quota(:remote_ip, remote_ip, _auth_method) do
    case :ets.lookup(@ets_table, remote_ip) do
      [] ->
        {:ok, quota} = ApiCallLimit.get_quota_db(:remote_ip, remote_ip)
        true = :ets.insert(@ets_table, {remote_ip, quota, quota})
        {:ok, quota}

      [{^remote_ip, :infinity, :infinity}] ->
        {:ok, :infinity}

      [{^remote_ip, api_calls_left, quota}] when api_calls_left <= 0 ->
        :ok = ApiCallLimit.update_usage_db(:remote_ip, remote_ip, quota + -api_calls_left)
        {:ok, quota} = ApiCallLimit.get_quota_db(:remote_ip, remote_ip)
        true = :ets.insert(@ets_table, {remote_ip, quota, quota})

        {:ok, quota}

      [{^remote_ip, api_calls_left, _}] ->
        {:ok, api_calls_left}
    end
  end

  @doc ~s"""
  """
  def update_usage(_type, _entity, :basic), do: :ok

  def update_usage(:user, %User{id: user_id} = user, count, _auth_method) do
    case :ets.lookup(@ets_table, user_id) do
      [] ->
        :ok = ApiCallLimit.update_usage_db(:user, user, count)
        {:ok, quota} = ApiCallLimit.get_quota_db(:user, user)
        true = :ets.insert(@ets_table, {user_id, quota, quota})
        :ok

      [{^user_id, :infinity, :infinity}] ->
        :ok

      [{^user_id, api_calls_left, _quota}] ->
        true = :ets.update_element(@ets_table, user_id, {2, api_calls_left - count})
        :ok
    end
  end

  def update_usage(:remote_ip, remote_ip, count, _auth_method) do
    case :ets.lookup(@ets_table, remote_ip) do
      [] ->
        :ok = ApiCallLimit.update_usage_db(:remote_ip, remote_ip, count)
        {:ok, quota} = ApiCallLimit.get_quota_db(:remote_ip, remote_ip)
        true = :ets.insert(@ets_table, {remote_ip, quota, quota})
        :ok

      [{^remote_ip, :infinity, :infinity}] ->
        :ok

      [{^remote_ip, api_calls_left, _quota}] ->
        true = :ets.update_element(@ets_table, remote_ip, {2, api_calls_left - count})
        :ok
    end
  end
end
