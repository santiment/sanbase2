defmodule SanbaseWeb.InactiveUsersController do
  @moduledoc """
  Controller for the inactive users CSV export.
  """

  use SanbaseWeb, :controller

  def download_csv(conn, %{"data" => csv_data}) do
    conn
    |> put_resp_content_type("text/csv")
    |> put_resp_header("content-disposition", "attachment; filename=\"inactive_users.csv\"")
    |> send_resp(200, csv_data)
  end

  def download_csv(conn, _params) do
    conn
    |> put_status(400)
    |> put_resp_content_type("text/plain")
    |> send_resp(400, "Missing CSV data parameter")
  end
end
