defmodule SanbaseWeb.GenericAdminAssignRoutes do
  @moduledoc false
  import Plug.Conn

  def init(options), do: options

  def call(conn, _opts) do
    assign(conn, :routes, SanbaseWeb.GenericAdminController.all_routes())
  end
end
