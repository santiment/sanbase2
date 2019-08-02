defmodule Sanbase.Model.CmcProject do
  use Ecto.Schema
  import Ecto.Changeset
  alias Sanbase.Repo
  alias Sanbase.Model.CmcProject

  schema "cmc_project" do
    belongs_to(:project, Project)

    field(:logos_uploaded_at, :naive_datetime)
    field(:logo_hash, :string)

    timestamps()
  end

  @doc false
  def changeset(%CmcProject{} = cmc_project, attrs \\ %{}) do
    cmc_project
    |> cast(attrs, [:project_id, :logo_hash, :logos_uploaded_at])
    |> validate_required([:project_id])
    |> unique_constraint(:project_id)
  end

  def by_project_id(project_id) do
    Repo.get_by(CmcProject, project_id: project_id)
  end

  def insert!(project_id) do
    %CmcProject{}
    |> CmcProject.changeset(%{project_id: project_id})
    |> Repo.insert!()
  end

  def get_or_insert(project_id) do
    {:ok, cmc_project} =
      Repo.transaction(fn ->
        by_project_id(project_id)
        |> case do
          nil -> insert!(project_id)
          project_id -> project_id
        end
      end)

    cmc_project
  end
end
