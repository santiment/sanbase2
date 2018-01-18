defmodule Sanbase.GithubTest do
  use Sanbase.DataCase, async: false

  alias Sanbase.Repo
  alias Sanbase.Github
  alias Sanbase.Model.Project

  test "available_projects returns projects with github link" do
    project = %Project{github_link: "https://github.com/santiment", ticker: "SAN", coinmarketcap_id: "santiment", name: "Santiment"}
    |> Repo.insert!

     %Project{github_link: "https://bitbucket.com/random", ticker: "RAN", coinmarketcap_id: "random", name: "Random"}
    |> Repo.insert!

    %Project{github_link: "", name: "No Source code"}
    |> Repo.insert!

    assert Github.available_projects == [project]
  end

  test "get_project_org parsing the github organization" do
    project = %Project{github_link: "https://github.com/santiment", ticker: "SAN", coinmarketcap_id: "santiment", name: "Santiment"}

    assert Github.get_project_org(project) == "santiment"

    project = %Project{github_link: "https://github.com/Santiment/sanbase2", ticker: "SAN", coinmarketcap_id: "santiment", name: "Santiment"}

    assert Github.get_project_org(project) == "santiment"

    project = %Project{github_link: "https://bitbucket.com/random", ticker: "RAN", coinmarketcap_id: "random", name: "Random"}

    assert Github.get_project_org(project) == nil

    project = %Project{github_link: "", name: "No Source code"}

    assert Github.get_project_org(project) == nil
  end
end
