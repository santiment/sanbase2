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
        conn

      _ ->
        conn
        |> send_resp(404, "Page Not Found")
        |> halt()
    end
  end
end
