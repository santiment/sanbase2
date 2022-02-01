defmodule Sanbase.Comment.PostComment do
  @moduledoc ~s"""
  A mapping table connecting comments and posts.

  This module is used to create, update, delete and fetch insight comments.
  """
  use Ecto.Schema

  import Ecto.Changeset

  schema "post_comments_mapping" do
    belongs_to(:comment, Sanbase.Comment)
    belongs_to(:post, Sanbase.Insight.Post)

    timestamps()
  end

  def changeset(%__MODULE__{} = mapping, attrs \\ %{}) do
    mapping
    |> cast(attrs, [:post_id, :comment_id])
    |> validate_required([:post_id, :comment_id])
    |> unique_constraint(:comment_id)
  end
end
