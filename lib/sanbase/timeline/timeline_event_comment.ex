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
end
