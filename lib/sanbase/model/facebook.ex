defmodule Sanbase.Model.Facebook do
  use Ecto.Schema
  import Ecto.Changeset
  alias Sanbase.Model.Facebook
  alias Sanbase.Model.Project


  schema "facebook" do
    field :likes, :integer
    field :link, :string
    belongs_to :project, Project
  end

  @doc false
  def changeset(%Facebook{} = facebook, attrs \\ %{}) do
    facebook
    |> cast(attrs, [:link, :likes, :project_id])
    |> validate_required([:project_id])
    |> unique_constraint(:project_id)
  end
end
