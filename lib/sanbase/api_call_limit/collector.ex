defmodule Sanbase.ApiCallLimit.Collector do
  use GenServer

  def start_link(args) do
    GenServer.start_link(__MODULE__, args)
  end

  def init(_args) do
    {:ok, _initial_state = []}
  end

  # In test environment we use call to make it synchronous. Otherwise in tests we need
  # to sleep for some time before checking the result
  case Application.compile_env(:sanbase, :env) do
    :test -> def update_usage(server, msg), do: GenServer.call(server, {:update_usage, msg})
    _ -> def update_usage(server, msg), do: GenServer.cast(server, {:update_usage, msg})
  end

  def get_quota(server, msg) do
    GenServer.call(server, {:get_quota, msg})
  end

  def handle_cast(
        {:update_usage, {entity_type, auth_method, entity_key, count, result_byte_size}},
        state
      ) do
    # Async, used in dev/prod env
    Sanbase.ApiCallLimit.ETS.update_usage(
      entity_type,
      auth_method,
      entity_key,
      count,
      result_byte_size
    )

    {:noreply, state}
  end

  def handle_call(
        {:update_usage, {entity_type, auth_method, entity_key, count, result_byte_size}},
        _from,
        state
      ) do
    # Symc, used in test env
    Sanbase.ApiCallLimit.ETS.update_usage(
      entity_type,
      auth_method,
      entity_key,
      count,
      result_byte_size
    )

    {:reply, :ok, state}
  end

  def handle_call({:get_quota, {entity_type, entity_key, auth_method}}, _from, state) do
    quota = Sanbase.ApiCallLimit.ETS.get_quota(entity_type, entity_key, auth_method)
    {:reply, quota, state}
  end
end
