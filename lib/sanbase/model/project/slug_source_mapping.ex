defmodule Sanbase.Model.Project.SlugSourceMapping do
  use Ecto.Schema

  import Ecto.Query
  import Ecto.Changeset

  alias Sanbase.Repo
  alias Sanbase.Model.Project

  @table "slug_source_mappings"

  schema @table do
    field(:source, :string)
    field(:source_slug, :string)

    belongs_to(:project, Project)
  end

  def changeset(%__MODULE__{} = ssm, attrs \\ %{}) do
    ssm
    |> cast(attrs, [:source, :source_slug, :project_id])
    |> validate_required([:source, :source_slug, :project_id])
    |> unique_constraint(:source_slug, name: :source_slug_unique_combination)
  end

  def create(attrs) do
    changeset_fn(%__MODULE__{}, attrs) |> Repo.insert()
  end

  def get_source_slug(%Project{id: project_id}, source) do
    from(
      ssm in __MODULE__,
      where: ssm.project_id == ^project_id and ssm.source == ^source,
      select: ssm.source_slug
    )
    |> Repo.one()
  end
end
