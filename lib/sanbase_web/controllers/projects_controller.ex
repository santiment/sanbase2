defmodule SanbaseWeb.ProjectsController do
  use SanbaseWeb, :controller

  alias Sanbase.Model.Project
  alias Sanbase.Repo

  import Ecto.Query

  def index(conn, _params) do
    projects = Project
    |> where([p], not is_nil(p.coinmarketcap_id) and not is_nil(p.ticker))
    |> preload(:latest_coinmarketcap_data)
    |> Repo.all

    render conn, "index.json", projects: projects
  end
end
