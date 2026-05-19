defmodule Sanbase.Project.SourceSlugMapping do
  use Ecto.Schema

  import Ecto.Query
  import Ecto.Changeset

  alias Sanbase.Repo
  alias Sanbase.Project

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

  @doc ~s"""
  Return the source slug (as known to `source`) for the project identified by
  `project_slug` (Sanbase slug), or `nil` if no mapping exists.
  """
  @spec get_source_slug(String.t(), String.t()) :: String.t() | nil
  def get_source_slug(project_slug, source) do
    from(
      ssm in __MODULE__,
      join: p in assoc(ssm, :project),
      where: ssm.source == ^source and p.slug == ^project_slug,
      select: ssm.slug,
      limit: 1
    )
    |> Repo.one()
  end

  def delete_mappings_for_source_and_slugs(source, slugs) do
    from(
      ssm in __MODULE__,
      where: ssm.source == ^source and ssm.slug in ^slugs
    )
    |> Repo.delete_all()
  end
end
