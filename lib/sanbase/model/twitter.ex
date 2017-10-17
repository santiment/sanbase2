defmodule Sanbase.Model.Twitter do
  use Ecto.Schema
  import Ecto.Changeset
  alias Sanbase.Model.Twitter
  alias Sanbase.Model.Project


  schema "twitter" do
    field :followers, :integer
    field :following, :integer
    field :joindate, :date
    field :likes, :integer
    field :link, :string
    field :tweets, :integer
    belongs_to :project, Project
  end

  @doc false
  def changeset(%Twitter{} = twitter, attrs \\ %{}) do
    twitter
    |> cast(attrs, [:link, :joindate, :tweets, :followers, :following, :likes])
    |> validate_required([:link, :joindate, :tweets, :followers, :following, :likes])
    |> unique_constraint(:project_id)
  end
end
