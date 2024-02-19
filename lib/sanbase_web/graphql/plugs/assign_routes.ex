defmodule SanbaseWeb.AssignRoutes do
  import Plug.Conn

  def init(options), do: options

  def call(conn, _opts) do
    assign(conn, :routes, SanbaseWeb.GenericController.all_routes())
  end
end
