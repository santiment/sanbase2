defmodule Sanbase.Repo.Migrations.PopulateGithubOrganizationsTable do
  use Ecto.Migration

  import Ecto.Query

  alias Sanbase.Repo
  alias Sanbase.Model.Project

  def up do
    Application.ensure_all_started(:tzdata)
    Application.ensure_all_started(:prometheus_ecto)
    Sanbase.Prometheus.EctoInstrumenter.setup()

    populate_github_organizations()
  end

  def down, do: :ok

  defp populate_github_organizations() do
    data =
      from(p in Project,
        where: not is_nil(p.github_link),
        select: {p.id, p.github_link}
      )
      |> Repo.all()

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
      project_id_github_org
      |> Enum.map(fn {id, org} ->
        %{project_id: id, organization: org}
      end)

    Repo.insert_all(Project.GithubOrganization, insert_data)
  end
end
