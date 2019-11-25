defmodule SanbaseWeb.MigratePricesController do
  use SanbaseWeb, :controller

  require Logger

  def migrate(conn, _params) do
    Task.Supervisor.async_nolink(Sanbase.TaskSupervisor, fn ->
      Sanbase.Prices.Migrate.run()
    end)

    send_response("OK", conn)
  end

  defp send_response(data, conn) do
    conn
    |> resp(200, data)
    |> send_resp()
  end
end
