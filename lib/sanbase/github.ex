defmodule Sanbase.Github do
  import Ecto.Query

  alias Sanbase.Model.Project
  alias Sanbase.Repo

  def available_projects do
    Project
    |> where([p], not is_nil(p.github_link) and not is_nil(p.coinmarketcap_id) and not is_nil(p.ticker))
    |> Repo.all
    |> Enum.filter(&get_project_org/1)
  end

  def get_project_org(%Project{github_link: github_link}) do
    case Regex.run(~r{https://(?:www.)?github.com/(.+)}, github_link) do
      [_, github_path] ->
        org = github_path
        |> String.downcase
        |> String.split("/")
        |> hd

        org
      nil ->
        nil
    end
  end
end
