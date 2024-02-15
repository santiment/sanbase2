defmodule Sanbase.Insight.PostTag do
  use Ecto.Schema
  import Ecto.Changeset

  schema "posts_tags" do
    belongs_to(:post, Sanbase.Insight.Post)
    belongs_to(:tag, Sanbase.Tag)
  end

  def changeset(post_tag, attrs \\ %{}) do
    post_tag
    |> cast(attrs, [:post_id, :tag_id])
    |> validate_required([:post_id, :tag_id])
  end
end
