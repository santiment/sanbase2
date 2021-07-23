defmodule Sanbase.Repo.Migrations.MigrateMissingeGithubOrganizations do
  use Ecto.Migration

  import Ecto.Query

  alias Sanbase.Repo
  alias Sanbase.Model.Project

  def up do
    Application.ensure_all_started(:tzdata)

    populate_github_organizations()
  end

  def down, do: :ok

  defp populate_github_organizations() do
    # Select all projects that have `github_link` but does not have
    # `github_organizations`. These projects have their github link
    # mistakenly added to the not appropriate, deprected field
    data =
      from(p in Project,
        full_join: gl in Project.GithubOrganization,
        on: p.id == gl.project_id,
        where: not is_nil(p.github_link) and is_nil(gl.project_id),
        preload: [:github_organizations]
      )
      |> Repo.all()

    project_id_github_org =
      data
      |> Enum.map(fn %Project{id: id, github_link: github_link} ->
        case Project.GithubOrganization.link_to_organization(github_link) do
          {:ok, org} -> {id, org}
          _ -> nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    insert_data =
      project_id_github_org
      |> Enum.map(fn {id, org} ->
        %{project_id: id, organization: org}
      end)

    Repo.insert_all(Project.GithubOrganization, insert_data, on_conflict: :nothing)
  end
end
