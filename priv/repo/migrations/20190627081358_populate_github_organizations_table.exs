defmodule Sanbase.Repo.Migrations.PopulateGithubOrganizationsTable do
  @moduledoc false
  use Ecto.Migration

  import Ecto.Query

  alias Sanbase.Project
  alias Sanbase.Repo

  def up do
    Application.ensure_all_started(:tzdata)

    populate_github_organizations()
  end

  def down, do: :ok

  defp populate_github_organizations do
    data = Repo.all(from(p in Project, where: not is_nil(p.github_link), select: {p.id, p.github_link}))

    project_id_github_org =
      data
      |> Enum.map(fn {id, github_link} ->
        case Project.GithubOrganization.link_to_organization(github_link) do
          {:ok, org} -> {id, org}
          _ -> nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    insert_data =
      Enum.map(project_id_github_org, fn {id, org} ->
        %{project_id: id, organization: org}
      end)

    Repo.insert_all(Project.GithubOrganization, insert_data)
  end
end
