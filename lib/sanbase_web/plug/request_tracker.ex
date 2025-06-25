defmodule SanbaseWeb.Plug.RequestTracker do
  @moduledoc """
  Plug to track active requests for graceful shutdown.

  This plug tracks when requests start and finish, allowing the graceful
  shutdown mechanism to wait for all active requests to complete.
  """

  import Plug.Conn
  require Logger

  def init(opts), do: opts

  def call(conn, _opts) do
    # Track request start
    Sanbase.GracefulShutdown.request_started()

    # Add a callback to track request finish
    conn
    |> put_private(:request_tracked, true)
    |> register_before_send(&track_request_finish/1)
  end

  defp track_request_finish(conn) do
    # Track request finish
    Sanbase.GracefulShutdown.request_finished()
    conn
  end
end
