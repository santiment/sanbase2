defmodule Sanbase.Timeline.TimelineEventComment do
  @moduledoc ~s"""
  A mapping table connecting comments and timeline events.

  This module is used to create, update, delete and fetch timeline events comments.
  """
  use Ecto.Schema

  import Ecto.{Query, Changeset}

  alias Sanbase.Repo
  alias Sanbase.Comment
  alias Sanbase.Timeline.TimelineEvent

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
  Create a new comment and link it to an insight.
  The operation is done in a transaction.
  """
  def create_and_link(timeline_event_id, user_id, parent_id, content) do
    Ecto.Multi.new()
    |> Ecto.Multi.run(
      :create_comment,
      fn _changes -> Comment.create(user_id, content, parent_id) end
    )
    |> Ecto.Multi.run(:link_comment_and_timeline_event, fn
      %{create_comment: comment} ->
        link(comment.id, timeline_event_id)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{create_comment: comment}} -> {:ok, comment}
      {:error, _name, error, _} -> {:error, error}
    end
  end

  def update_comment(comment_id, user_id, content) do
    Comment.update(comment_id, user_id, content)
  end

  def delete_comment(comment_id, user_id) do
    Comment.delete(comment_id, user_id)
  end

  def link(comment_id, timeline_event_id) do
    %__MODULE__{}
    |> changeset(%{comment_id: comment_id, timeline_event_id: timeline_event_id})
    |> Repo.insert()
  end

  def get_comments(timeline_event_id, %{limit: limit} = args) do
    cursor = Map.get(args, :cursor)

    timeline_event_comments_query(timeline_event_id)
    |> apply_cursor(cursor)
    |> order_by([c], c.inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end

  def get_subcomments(comment_id, %{limit: limit}) do
    Comment.get_subcomments(comment_id, limit)
  end

  defp timeline_event_comments_query(timeline_event_id) do
    from(p in __MODULE__,
      where: p.timeline_event_id == ^timeline_event_id,
      preload: [:comment, comment: :user]
    )
  end

  defp apply_cursor(query, %{type: :before, datetime: datetime}) do
    from(c in query, where: c.inserted_at < ^datetime)
  end

  defp apply_cursor(query, %{type: :after, datetime: datetime}) do
    from(c in query, where: c.inserted_at >= ^datetime)
  end

  defp apply_cursor(query, nil), do: query
end
