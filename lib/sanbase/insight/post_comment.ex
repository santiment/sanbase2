defmodule Sanbase.Insight.PostComment do
  @moduledoc ~s"""
  A mapping table connecting comments and posts.

  This module is used to create, update, delete and fetch insight comments.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Sanbase.Comment
  alias Sanbase.Insight.Post
  alias Sanbase.Comment.EntityComment

  schema "post_comments_mapping" do
    belongs_to(:comment, Comment)
    belongs_to(:post, Post)

    timestamps()
  end

  def changeset(%__MODULE__{} = mapping, attrs \\ %{}) do
    mapping
    |> cast(attrs, [:post_id, :comment_id])
    |> validate_required([:post_id, :comment_id])
    |> unique_constraint(:comment_id)
  end

  @doc ~s"""
  Create a new comment and link it to an insight.
  The operation is done in a transaction.
  """
  def create_and_link(entity_id, user_id, parent_id, content) do
    EntityComment.create_and_link(entity_id, user_id, parent_id, content, :insight)
  end

  def link(comment_id, entity_id) do
    EntityComment.link(comment_id, entity_id, :insight)
  end

  def get_comments(entity_id, args) do
    EntityComment.get_comments(entity_id, args, :insight)
  end
end
