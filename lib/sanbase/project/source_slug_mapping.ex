defmodule Sanbase.Project.SourceSlugMapping do
  @moduledoc false
  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query

  alias Sanbase.Project
  alias Sanbase.Repo

  @table "source_slug_mappings"

  schema @table do
    field(:source, :string)
    field(:slug, :string)

    belongs_to(:project, Project)
  end

  def changeset(%__MODULE__{} = ssm, attrs \\ %{}) do
    ssm
    |> cast(attrs, [:source, :slug, :project_id])
    |> validate_required([:source, :slug, :project_id])
  end

  def create(attrs) do
    %__MODULE__{} |> changeset(attrs) |> Repo.insert()
  end

  def remove(project_id, source) do
    Repo.delete_all(from(ssm in __MODULE__, where: ssm.project_id == ^project_id and ssm.source == ^source))
  end

  def get_source_slug_mappings(source) do
    Repo.all(
      from(ssm in __MODULE__, join: p in assoc(ssm, :project), where: ssm.source == ^source, select: {ssm.slug, p.slug})
    )
  end

  def get_slug(%Project{id: project_id}, source) do
    Repo.one(from(ssm in __MODULE__, where: ssm.project_id == ^project_id and ssm.source == ^source, select: ssm.slug))
  end
end
