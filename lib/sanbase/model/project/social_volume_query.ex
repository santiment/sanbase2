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
    |> validate_required(:query)
    |> unique_constraint(:project_id)
  end

  defimpl String.Chars do
    def to_string(%{query: query}), do: query
  end
end
