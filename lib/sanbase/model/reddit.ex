defmodule Sanbase.Model.Reddit do
  use Ecto.Schema
  import Ecto.Changeset
  alias Sanbase.Model.Reddit
  alias Sanbase.Model.Project


  schema "reddit" do
    field :link, :string
    field :subscribers, :integer
    belongs_to :project, Project
  end

  @doc false
  def changeset(%Reddit{} = reddit, attrs \\ %{}) do
    reddit
    |> cast(attrs, [:link, :subscribers, :project_id])
    |> validate_required([:project_id])
    |> unique_constraint(:project_id)
  end
end
