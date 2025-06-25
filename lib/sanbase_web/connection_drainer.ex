defmodule SanbaseWeb.ConnectionDrainer do
  @moduledoc ~s"""
  Implement a graceful shutdown for the Phoenix server by draining connections.

  In the Supervision tree, processes start in the order they are defined
  and are stopped in the reverse order. This process should be put after the
  Endpoint.
  """
  use GenServer

  require Logger

  def child_spec(options) when is_list(options) do
    ranch_ref = Keyword.fetch!(options, :ranch_ref)
    shutdown = Keyword.fetch!(options, :shutdown)

    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [ranch_ref]},
      shutdown: shutdown
    }
  end

  def start_link(ranch_ref) do
    GenServer.start_link(__MODULE__, ranch_ref)
  end

  def init(ranch_ref) do
    Process.flag(:trap_exit, true)
    {:ok, ranch_ref}
  end

  def terminate(_reason, ranch_ref) do
    # Stop accepting new connections
    :ok = :ranch.suspend_listener(ranch_ref)
    # Wait until the connections are all finished.
    # If it takes more time, the `:shutdown` timeout will kick in
    # and kill this process. This way we have a balance between
    # waiting for most connections to finish, but not waiting too long
    # or getting stuck.
    :ok = :ranch.wait_for_connections(ranch_ref, :==, 0)
  end
end
