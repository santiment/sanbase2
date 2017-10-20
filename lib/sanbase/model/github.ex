defmodule Sanbase.Model.Github do
  use Ecto.Schema
  import Ecto.Changeset
  alias Sanbase.Model.Github
  alias Sanbase.Model.Project


  schema "github" do
    field :commits, :integer
    field :contributors, :integer
    field :link, :string
    belongs_to :project, Project
  end

  @doc false
  def changeset(%Github{} = github, attrs \\ %{}) do
    github
    |> cast(attrs, [:link, :commits, :contributors, :project_id])
    |> validate_required([:link, :commits, :contributors, :project_id])
    |> unique_constraint(:project_id)
  end
end
