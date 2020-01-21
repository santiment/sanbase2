defmodule Sanbase.Timeline.TimelineEventComment do
  @moduledoc ~s"""
  A mapping table connecting comments and timeline events.

  This module is used to create, update, delete and fetch timeline events comments.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Sanbase.Comment
  alias Sanbase.Timeline.TimelineEvent
  alias Sanbase.Comment.EntityComment

  schema "timeline_event_comments_mapping" do
    belongs_to(:comment, Comment)
    belongs_to(:timeline_event, TimelineEvent)

    timestamps()
  end

  def changeset(%__MODULE__{} = mapping, attrs \\ %{}) do
    mapping
    |> cast(attrs, [:timeline_event_id, :comment_id])
    |> validate_required([:timeline_event_id, :comment_id])
    |> unique_constraint(:comment_id)
  end

  @doc ~s"""
  Create a new comment and link it to a timeline event.
  The operation is done in a transaction.
  """
  def create_and_link(entity_id, user_id, parent_id, content) do
    EntityComment.create_and_link(entity_id, user_id, parent_id, content, :timeline_event)
  end

  def link(comment_id, entity_id) do
    EntityComment.link(comment_id, entity_id, :timeline_event)
  end

  def update_comment(comment_id, user_id, content) do
    Comment.update(comment_id, user_id, content)
  end

  def delete_comment(comment_id, user_id) do
    Comment.delete(comment_id, user_id)
  end

  def get_comments(entity_id, args) do
    EntityComment.get_comments(entity_id, args, :timeline_event)
  end

  def get_subcomments(comment_id, %{limit: limit}) do
    Comment.get_subcomments(comment_id, limit)
  end
end
