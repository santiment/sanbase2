defmodule SanbaseWeb.MigratePricesController do
  use SanbaseWeb, :controller

  require Logger

  @spec migrate(Plug.Conn.t(), map) :: Plug.Conn.t()
  def migrate(conn, %{"from" => from}) do
    Task.Supervisor.async_nolink(Sanbase.TaskSupervisor, fn ->
      Sanbase.Prices.Migrate.run(from)
    end)

    send_response("OK", conn)
  end

  defp send_response(data, conn) do
    conn
    |> resp(200, data)
    |> send_resp()
  end
end
