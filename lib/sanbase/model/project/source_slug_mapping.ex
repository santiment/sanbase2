defmodule Sanbase.Model.Project.SourceSlugMapping do
  use Ecto.Schema

  import Ecto.Query
  import Ecto.Changeset

  alias Sanbase.Repo
  alias Sanbase.Model.Project

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
    changeset(%__MODULE__{}, attrs) |> Repo.insert()
  end

  def remove(project_id, source) do
    from(
      ssm in __MODULE__,
      where: ssm.project_id == ^project_id and ssm.source == ^source
    )
    |> Repo.delete_all()
  end

  def get_source_slug_mappings(source) do
    from(
      ssm in __MODULE__,
      join: p in assoc(ssm, :project),
      where: ssm.source == ^source,
      select: {ssm.slug, p.slug}
    )
    |> Repo.all()
  end

  def get_slug(%Project{id: project_id}, source) do
    from(
      ssm in __MODULE__,
      where: ssm.project_id == ^project_id and ssm.source == ^source,
      select: ssm.slug
    )
    |> Repo.one()
  end
end
