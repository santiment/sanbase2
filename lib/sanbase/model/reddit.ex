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
    |> cast(attrs, [:link, :subscribers])
    |> validate_required([:link, :subscribers])
    |> unique_constraint(:project_id)
  end
end
