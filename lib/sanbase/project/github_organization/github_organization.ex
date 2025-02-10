defmodule Sanbase.Project.GithubOrganization do
  @moduledoc ~s"""
  Module for managing the "github_organziations" postgres table

  In order to have multiple github organizations per project we store
  the github data in a separate table
  """

  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query

  alias Sanbase.Project
  alias Sanbase.Repo

  schema "github_organizations" do
    field(:organization, :string)
    belongs_to(:project, Project)
  end

  def changeset(%__MODULE__{} = org, attrs \\ %{}) do
    org
    |> cast(attrs, [:organization, :project_id])
    |> validate_required([:organization])
  end

  def get(project_id, organization) do
    query =
      from(go in __MODULE__,
        where: go.project_id == ^project_id and go.organization == ^organization
      )

    case Repo.all(query) do
      [%__MODULE__{} = org] ->
        {:ok, org}

      [] ->
        {:error, "The project with id #{project_id} does not have a github organization #{organization}"}
    end
  end

  def add_github_organization(%Project{} = project, organization) do
    add_github_organization(project.id, organization)
  end

  def add_github_organization(project_id, organization) do
    %__MODULE__{}
    |> changeset(%{organization: organization, project_id: project_id})
    |> Repo.insert()
  end

  def remove_github_organization(%Project{} = project, organization) do
    remove_github_organization(project.id, organization)
  end

  def remove_github_organization(project_id, organization) do
    with {:ok, record} <- get(project_id, organization) do
      Repo.delete(record)
    end
  end

  def organizations_of(%Project{} = project) do
    project
    |> Repo.preload(:github_organizations)
    |> Map.get(:github_organizations, [])
    |> Enum.map(& &1.organization)
  end

  def organizations_of(project_id) when is_integer(project_id) and project_id > 0 do
    project_id
    |> organizations_query()
    |> Repo.all()
  end

  def organization_to_link(organization) do
    "https://github.com/#{organization}"
  end

  def link_to_organization(nil), do: {:error, "Github link not valid. Got: nil"}

  def link_to_organization(github_link) when is_binary(github_link) do
    case Regex.run(~r{http(?:s)?://(?:www.)?github.com/(.+)}, github_link) do
      [_, github_path] ->
        org =
          github_path
          |> String.downcase()
          |> String.split("/")
          |> hd()

        {:ok, org}

      nil ->
        {:error, "Github link not valid. Got: #{github_link}"}
    end
  end

  defp organizations_query(project_id) do
    from(org in __MODULE__,
      where: org.project_id == ^project_id,
      select: org.organization
    )
  end
end
