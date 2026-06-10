defmodule SanbaseWeb.Plug.AdminPodOnly do
  @moduledoc ~s"""
  Check if the container type allows access to the admin dashboard
  endpoints. T
  """

  @behaviour Plug

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _) do
    case Sanbase.ApplicationUtils.container_type() do
      # The `all` type is used only when developing locally.
      type when type in ["admin", "all"] ->
        # CSRF protection is intentionally skipped for the admin panel. This is
        # acceptable ONLY because the admin panel is served exclusively from the
        # network-isolated admin pod (any other pod returns 404 below) and is not
        # reachable from the public internet. If the admin panel is ever exposed
        # more broadly, this skip must be removed and forms must send CSRF tokens.
        Plug.Conn.put_private(conn, :plug_skip_csrf_protection, true)

      _ ->
        conn
        |> send_resp(404, "Page Not Found")
        |> halt()
    end
  end
end
