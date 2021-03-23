defmodule Sanbase.Model.Project.SocialVolumeQuery do
  use Ecto.Schema

  import Ecto.Changeset
  alias Sanbase.Model.Project

  schema "project_social_volume_query" do
    field(:query, :string)
    belongs_to(:project, Project)
  end

  def changeset(%__MODULE__{} = query, attrs \\ %{}) do
    query
    |> cast(attrs, [:query, :project_id])
    |> validate_required(:query)
    |> unique_constraint(:project_id)
  end

  def default_query(%Project{} = project) do
    %Project{ticker: ticker, name: name, slug: slug} = project

    [ticker, name, slug]
    |> Enum.reject(&is_nil/1)
    |> Enum.map(fn elem -> ~s/"#{elem}"/ end)
    |> Enum.map(&String.downcase/1)
    |> Enum.uniq()
    |> Enum.join(" OR ")
  end
end

defimpl String.Chars, for: Sanbase.Model.Project.SocialVolumeQuery do
  import Sanbase.Model.Project.SocialVolumeQuery, only: [default_query: 1]

  def to_string(%{query: nil, project: project}) do
    default_query(project)
  end

  def to_string(%{query: query}) do
    query
  end
end
