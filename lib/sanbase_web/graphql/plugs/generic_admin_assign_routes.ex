defmodule SanbaseWeb.GenericAdminAssignRoutes do
  import Plug.Conn

  def init(options), do: options

  def call(conn, _opts) do
    all_routes = SanbaseWeb.GenericAdminController.all_routes(conn)
    assign(conn, :routes, all_routes)
  end
end
