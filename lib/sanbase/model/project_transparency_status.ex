defmodule Sanbase.Model.ProjectTransparencyStatus do
  use Ecto.Schema
  import Ecto.Changeset
  alias Sanbase.Model.ProjectTransparencyStatus
  alias Sanbase.Model.Project

  schema "project_transparency_statuses" do
    field(:name, :string)
    has_many(:projects, Project)
  end

  @doc false
  def changeset(%ProjectTransparencyStatus{} = project_transparency_status, attrs \\ %{}) do
    project_transparency_status
    |> cast(attrs, [:name])
    |> validate_required([:name])
    |> unique_constraint(:name)
  end
end
