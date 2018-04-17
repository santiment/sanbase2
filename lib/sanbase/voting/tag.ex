defmodule Sanbase.Voting.Tag do
  use Ecto.Schema

  import Ecto.Changeset

  alias Sanbase.Voting.{Tag, Post}

  schema "tags" do
    field(:name, :string)

    many_to_many(:posts, Post, join_through: "posts_tags")
  end

  def changeset(%Tag{} = tag, attrs \\ %{}) do
    tag
    |> cast(attrs, [:name])
    |> validate_required([:name])
    |> unique_constraint(:name, name: :tags_name_index)
  end
end
