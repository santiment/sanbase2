defmodule SanbaseWeb.HealthController do
  @moduledoc """
  Health check controller for Kubernetes probes.
  """

  use SanbaseWeb, :controller

  def health(conn, _params) do
    # Basic health check - can be extended with database connectivity,
    # external service checks, etc.
    conn
    |> put_status(200)
    |> json(%{
      status: "healthy",
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      active_requests: Sanbase.GracefulShutdown.get_active_requests_count()
    })
  end
end
