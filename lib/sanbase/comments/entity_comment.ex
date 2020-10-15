defmodule Sanbase.Comments.EntityComment do
  @moduledoc """
  Module for dealing with comments for certain entities.
  """
  import Ecto.Query

  alias Sanbase.Repo
  alias Sanbase.Comment
  alias Sanbase.Timeline.TimelineEventComment
  alias Sanbase.Insight.PostComment
  alias Sanbase.ShortUrl.ShortUrlComment

  @type entity :: :insight | :timeline_event | :short_url

  @spec create_and_link(
          entity,
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer() | nil,
          String.t()
        ) ::
          {:ok, %Comment{}} | {:error, any()}
  def create_and_link(entity, entity_id, user_id, parent_id, content) do
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

  @spec link(:short_url, non_neg_integer(), non_neg_integer()) ::
          {:ok, %ShortUrlComment{}} | {:error, Ecto.Changeset.t()}
  def link(:short_url, entity_id, comment_id) do
    %ShortUrlComment{}
    |> ShortUrlComment.changeset(%{comment_id: comment_id, short_url_id: entity_id})
    |> Repo.insert()
  end

  @spec get_comments(entity, non_neg_integer() | nil, map()) :: [%Comment{}]
  def get_comments(entity, entity_id, %{limit: limit} = args) do
    cursor = Map.get(args, :cursor) || %{}
    order = Map.get(cursor, :order, :asc)

    entity_comments_query(entity, entity_id)
    |> apply_cursor(cursor)
    |> order_by([c], [{^order, c.inserted_at}])
    |> limit(^limit)
    |> Repo.all()
  end

  # Private Functions

  defp maybe_add_entity_id_clause(query, _field, nil), do: query

  defp maybe_add_entity_id_clause(query, field, entity_id) do
    query
    |> where([elem], field(elem, ^field) == ^entity_id)
  end

  defp entity_comments_query(:timeline_event, entity_id) do
    from(
      comment in TimelineEventComment,
      preload: [:comment, comment: :user]
    )
    |> maybe_add_entity_id_clause(:timeline_event_id, entity_id)
  end

  defp entity_comments_query(:insight, entity_id) do
    from(comment in PostComment,
      preload: [:comment, comment: :user]
    )
    |> maybe_add_entity_id_clause(:post_id, entity_id)
  end

  defp entity_comments_query(:short_url, entity_id) do
    from(comment in ShortUrlComment,
      preload: [:comment, comment: :user]
    )
    |> maybe_add_entity_id_clause(:short_url_id, entity_id)
  end

  defp apply_cursor(query, %{type: :before, datetime: datetime}) do
    from(c in query, where: c.inserted_at <= ^(datetime |> DateTime.to_naive()))
  end

  defp apply_cursor(query, %{type: :after, datetime: datetime}) do
    from(c in query, where: c.inserted_at >= ^(datetime |> DateTime.to_naive()))
  end

  defp apply_cursor(query, _), do: query
end
