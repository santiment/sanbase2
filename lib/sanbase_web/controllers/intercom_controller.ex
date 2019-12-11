defmodule SanbaseWeb.IntercomController do
  use SanbaseWeb, :controller

  require Logger

  def get_user_data(conn, %{"user_id" => user_id}) do
    json = Sanbase.Intercom.get_data_for_user(user_id)
    send_response(json, conn)
  end

  def sync_users(conn, _params) do
    Task.Supervisor.async_nolink(Sanbase.TaskSupervisor, fn ->
      Sanbase.Intercom.sync_users()
    end)

    send_response("OK", conn)
  end

  defp send_response(data, conn) do
    conn
    |> resp(200, data)
    |> send_resp()
  end
end
