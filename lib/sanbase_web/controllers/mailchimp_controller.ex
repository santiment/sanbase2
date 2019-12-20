defmodule SanbaseWeb.MailchimpController do
  use SanbaseWeb, :controller

  require Logger

  def sync_users(conn, _params) do
    Task.Supervisor.async_nolink(Sanbase.TaskSupervisor, fn ->
      Sanbase.Email.Mailchimp.run()
    end)

    send_response("OK", conn)
  end

  defp send_response(data, conn) do
    conn
    |> resp(200, data)
    |> send_resp()
  end
end
