defmodule Sanbase.Voting.Tag do
  use Ecto.Schema

  alias Sanbase.Voting.Post

  schema "tags" do
    field(:name, :string)

    many_to_many(:posts, Post, join_through: "posts_tags")
  end
end
