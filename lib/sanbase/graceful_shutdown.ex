defmodule Sanbase.GracefulShutdown do
  @moduledoc """
  Handles graceful shutdown of the Phoenix application.

  When a SIGTERM signal is received, this module:
  1. Stops accepting new requests by shutting down the endpoint
  2. Waits for existing requests to complete (up to 30 seconds)
  3. Forces shutdown if timeout is reached
  """

  use GenServer
  require Logger

  @timeout 30_000

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    # Set up signal handling for SIGTERM
    :os.set_signal(:sigterm, :handle)

    Logger.info("Graceful shutdown handler started")
    {:ok, %{shutdown_started: false, active_requests: 0}}
  end

  def handle_info({:os_signal, :sigterm, _info}, state) do
    Logger.info("Received SIGTERM signal, starting graceful shutdown")
    start_graceful_shutdown(state)
  end

  def handle_info({:os_signal, :sigint, _info}, state) do
    Logger.info("Received SIGINT signal, starting graceful shutdown")
    start_graceful_shutdown(state)
  end

  def handle_info(:timeout, %{shutdown_started: true} = state) do
    Logger.warning("Graceful shutdown timeout reached, forcing shutdown")
    force_shutdown()
  end

  def handle_info(:timeout, state) do
    {:noreply, state}
  end

  def handle_call({:request_started}, _from, state) do
    new_state = %{state | active_requests: state.active_requests + 1}
    {:reply, :ok, new_state}
  end

  def handle_call({:request_finished}, _from, state) do
    new_state = %{state | active_requests: state.active_requests - 1}

    if new_state.shutdown_started and new_state.active_requests == 0 do
      Logger.info("All requests completed, shutting down")
      force_shutdown()
    end

    {:reply, :ok, new_state}
  end

  def handle_call(:get_active_requests, _from, state) do
    {:reply, state.active_requests, state}
  end

  defp start_graceful_shutdown(state) do
    Logger.info("Starting graceful shutdown process")

    # Stop accepting new requests by shutting down the endpoint
    stop_endpoint()

    # Set a timeout to force shutdown if needed
    Process.send_after(self(), :timeout, @timeout)

    # Check if there are any active requests
    active_requests = get_active_requests()

    if active_requests == 0 do
      Logger.info("No active requests, shutting down immediately")
      force_shutdown()
    else
      Logger.info("Waiting for #{active_requests} active requests to complete")
      {:noreply, %{state | shutdown_started: true, active_requests: active_requests}}
    end
  end

  defp stop_endpoint do
    Logger.info("Stopping Phoenix endpoint to prevent new requests")

    # Stop the endpoint gracefully
    case Process.whereis(SanbaseWeb.Endpoint) do
      nil ->
        Logger.warning("Endpoint process not found")

      pid ->
        # Stop accepting new connections
        Phoenix.Endpoint.stop(SanbaseWeb.Endpoint)
        Logger.info("Phoenix endpoint stopped")
    end
  end

  defp get_active_requests do
    # Get the current active requests count from our state
    case GenServer.call(__MODULE__, :get_active_requests, 1000) do
      count when is_integer(count) -> count
      _ -> 0
    end
  end

  defp force_shutdown do
    Logger.info("Forcing application shutdown")
    # Stop the application
    Application.stop(:sanbase)
    # Exit the process
    System.halt(0)
  end

  # Public API for tracking requests
  def request_started do
    try do
      GenServer.call(__MODULE__, {:request_started}, 1000)
    catch
      :exit, _ -> :ok
    end
  end

  def request_finished do
    try do
      GenServer.call(__MODULE__, {:request_finished}, 1000)
    catch
      :exit, _ -> :ok
    end
  end

  def get_active_requests_count do
    try do
      GenServer.call(__MODULE__, :get_active_requests, 1000)
    catch
      :exit, _ -> 0
    end
  end
end
