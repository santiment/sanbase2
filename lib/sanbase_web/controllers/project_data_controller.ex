defmodule SanbaseWeb.ProjectDataController do
  use SanbaseWeb, :controller

  require Logger

  # Used in production mode to serve the reactjs application
  def data(conn, _params) do
    json_each_row = "haha"

    conn
    |> put_resp_header("content-type", "application/json; charset=utf-8")
    |> Plug.Conn.send_resp(200, json_each_row)
  end

  defp get_data() do
    projects =
      Sanbase.Model.Project.List.projects()
      |> Enum.map(fn project ->
        %{slug: slug, infrastructure: infr} = project
      end)

    %{
      slug: "",
      github_repositories: [],
      decimals: [],
      contract: "",
      infrastructure: ""
    }
  end
end
