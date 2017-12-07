defmodule Sanbase.Github do
  import Ecto.Query

  alias Sanbase.Model.Project
  alias Sanbase.Repo

  def available_projects do
    Project
    |> where([p], not is_nil(p.github_link) and not is_nil(p.coinmarketcap_id) and not is_nil(p.ticker))
    |> Repo.all
  end
end
