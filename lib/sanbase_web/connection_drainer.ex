defmodule SanbaseWeb.ConnectionDrainer do
  @moduledoc ~s"""
  Implement a graceful shutdown for the Phoenix server by draining connections.

  In the Supervision tree, processes start in the order they are defined
  and are stopped in the reverse order. This process should be put after the
  Endpoint.
  """
  use GenServer

  def child_spec(options) when is_list(options) do
    endpoint = Keyword.fetch!(options, :endpoint)
    shutdown = Keyword.fetch!(options, :shutdown)
    name = Keyword.get(options, :name, __MODULE__)

    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [endpoint, [name: name]]},
      shutdown: shutdown
    }
  end

  def start_link(endpoint, opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, endpoint, name: name)
  end

  def init(endpoint) do
    Process.flag(:trap_exit, true)
    {:ok, endpoint}
  end

  def terminate(reason, endpoint) do
    # If we're in terminating state, the Logger does not work here for some reason
    IO.puts("[#{DateTime.utc_now(:second)}][ConnectionDrainer] Terminating with reason #{reason}")

    case safe_bandit_pid(endpoint) do
      {:ok, server_pid} ->
        # Stop accepting new connections
        :ok = ThousandIsland.suspend(server_pid)

        {:ok, running_connections} = ThousandIsland.connection_pids(server_pid)

        IO.puts(
          "[#{DateTime.utc_now(:second)}][ConnectionDrainer] Stopped accepting new connections. Waiting for #{length(running_connections)} connections to finish."
        )

        # Wait until the connections are all finished.
        # If it takes more time, the `:shutdown` timeout will kick in
        # and kill this process. This way we have a balance between
        # waiting for most connections to finish, but not waiting too long
        # or getting stuck.
        wait_for_drain(server_pid)

        IO.puts(
          "[#{DateTime.utc_now(:second)}][ConnectionDrainer] Finished draining connections."
        )

      _ ->
        IO.puts(
          "[#{DateTime.utc_now(:second)}][ConnectionDrainer] No HTTP server found, nothing to drain."
        )
    end
  end

  defp safe_bandit_pid(endpoint) do
    Bandit.PhoenixAdapter.bandit_pid(endpoint, :http)
  catch
    :exit, _ -> {:error, :no_server_found}
  end

  defp wait_for_drain(server_pid) do
    case ThousandIsland.connection_pids(server_pid) do
      {:ok, []} ->
        :ok

      :error ->
        :ok

      {:ok, _pids} ->
        Process.sleep(100)
        wait_for_drain(server_pid)
    end
  end
end
