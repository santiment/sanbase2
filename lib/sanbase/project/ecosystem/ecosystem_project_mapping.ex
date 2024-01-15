defmodule Sanbase.ProjectEcosystemMapping do
  use Ecto.Schema

  import Ecto.Changeset
  alias Sanbase.Project
  alias Sanbase.Ecosystem

  schema "project_ecosystem_mappings" do
    belongs_to(:project, Project)
    belongs_to(:ecosystem, Ecosystem)
    timestamps()
  end

  def changeset(%__MODULE__{} = mapping, attrs) do
    mapping
    |> cast(attrs, [:project_id, :ecosystem_id])
    |> validate_required([:project_id, :ecosystem_id])
  end

  def create(project_id, ecosystem_id) do
    %__MODULE__{}
    |> changeset(%{project_id: project_id, ecosystem_id: ecosystem_id})
    |> Sanbase.Repo.insert()
  end
end
