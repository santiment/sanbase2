defmodule Sanbase.Comment.EntityComment do
  import Ecto.Query

  alias Sanbase.Repo
  alias Sanbase.Comment
  alias Sanbase.Timeline.TimelineEventComment
  alias Sanbase.Insight.PostComment

  @entities [:insight, :timeline_event]

  def create_and_link(entity_id, user_id, parent_id, content, entity) when entity in @entities do
    Ecto.Multi.new()
    |> Ecto.Multi.run(
      :create_comment,
      fn _changes -> Comment.create(user_id, content, parent_id) end
    )
    |> Ecto.Multi.run(:link_comment_and_entity, fn
      %{create_comment: comment} ->
        link(comment.id, entity_id, entity)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{create_comment: comment}} -> {:ok, comment}
      {:error, _name, error, _} -> {:error, error}
    end
  end

  def link(comment_id, entity_id, :timeline_event) do
    %TimelineEventComment{}
    |> TimelineEventComment.changeset(%{
      comment_id: comment_id,
      timeline_event_id: entity_id
    })
    |> Repo.insert()
  end

  def link(comment_id, entity_id, :insight) do
    %PostComment{}
    |> PostComment.changeset(%{comment_id: comment_id, post_id: entity_id})
    |> Repo.insert()
  end

  def get_comments(entity_id, %{limit: limit} = args, entity) when entity in @entities do
    cursor = Map.get(args, :cursor)

    entity_comments_query(entity_id, entity)
    |> apply_cursor(cursor)
    |> order_by([c], c.inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end

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
    from(c in query, where: c.inserted_at < ^datetime)
  end

  defp apply_cursor(query, %{type: :after, datetime: datetime}) do
    from(c in query, where: c.inserted_at >= ^datetime)
  end

  defp apply_cursor(query, nil), do: query
end
