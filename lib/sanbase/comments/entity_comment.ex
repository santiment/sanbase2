defmodule Sanbase.Comments.EntityComment do
  @entities [:insight, :timeline_event]

  @moduledoc """
  Module for dealing with comments for certain entities.
  Current list of supported entities: #{inspect(@entities)}
  """
  import Ecto.Query

  alias Sanbase.Repo
  alias Sanbase.Comment
  alias Sanbase.Timeline.TimelineEventComment
  alias Sanbase.Insight.PostComment

  @type entity :: :insight | :timeline_event

  @spec create_and_link(
          entity,
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer() | nil,
          String.t()
        ) ::
          {:ok, %Comment{}} | {:error, any()}
  def create_and_link(entity, entity_id, user_id, parent_id, content) when entity in @entities do
    Ecto.Multi.new()
    |> Ecto.Multi.run(
      :create_comment,
      fn _repo, _changes -> Comment.create(user_id, content, parent_id) end
    )
    |> Ecto.Multi.run(:link_comment_and_entity, fn
      _repo, %{create_comment: comment} ->
        link(entity, entity_id, comment.id)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{create_comment: comment}} -> {:ok, comment}
      {:error, _name, error, _} -> {:error, error}
    end
  end

  @spec link(:insight, non_neg_integer(), non_neg_integer()) ::
          {:ok, %PostComment{}} | {:error, Ecto.Changeset.t()}
  def link(:insight, entity_id, comment_id) do
    %PostComment{}
    |> PostComment.changeset(%{comment_id: comment_id, post_id: entity_id})
    |> Repo.insert()
  end

  @spec link(:timeline_event, non_neg_integer(), non_neg_integer()) ::
          {:ok, %TimelineEventComment{}} | {:error, Ecto.Changeset.t()}
  def link(:timeline_event, entity_id, comment_id) do
    %TimelineEventComment{}
    |> TimelineEventComment.changeset(%{
      comment_id: comment_id,
      timeline_event_id: entity_id
    })
    |> Repo.insert()
  end

  @spec get_comments(entity, non_neg_integer(), map()) :: [%Comment{}]
  def get_comments(entity, entity_id, %{limit: limit} = args) when entity in @entities do
    cursor = Map.get(args, :cursor)

    entity_comments_query(entity_id, entity)
    |> apply_cursor(cursor)
    |> order_by([c], c.inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end

  # private functions
  defp entity_comments_query(entity_id, :timeline_event) do
    from(p in Sanbase.Timeline.TimelineEventComment,
      where: p.timeline_event_id == ^entity_id,
      preload: [:comment, comment: :user]
    )
  end

  defp entity_comments_query(entity_id, :insight) do
    from(p in Sanbase.Insight.PostComment,
      where: p.post_id == ^entity_id,
      preload: [:comment, comment: :user]
    )
  end

  defp apply_cursor(query, %{type: :before, datetime: datetime}) do
    from(c in query, where: c.inserted_at <= ^(datetime |> DateTime.to_naive()))
  end

  defp apply_cursor(query, %{type: :after, datetime: datetime}) do
    from(c in query, where: c.inserted_at >= ^(datetime |> DateTime.to_naive()))
  end

  defp apply_cursor(query, nil), do: query
end
