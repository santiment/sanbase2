defmodule SanbaseWeb.Graphql.Resolvers.CommentResolver do
  alias Sanbase.Comment
  alias Sanbase.Comments.EntityComment

  # # Note: deprecated - should be removed if not used by frontend
  def create_comment(
        _root,
        %{insight_id: post_id, content: content} = args,
        %{context: %{auth: %{current_user: user}}}
      ) do
    EntityComment.create_and_link(:insight, post_id, user.id, Map.get(args, :parent_id), content)
  end

  def create_comment(
        _root,
        %{entity_type: entity_type, id: id, content: content} = args,
        %{context: %{auth: %{current_user: user}}}
      ) do
    EntityComment.create_and_link(entity_type, id, user.id, Map.get(args, :parent_id), content)
  end

  def create_comment(_root, _args, _resolution), do: {:error, "Invalid args for createComment"}

  @spec update_comment(any, %{comment_id: any, content: any}, %{
          context: %{auth: %{current_user: atom | map}}
        }) :: any
  def update_comment(
        _root,
        %{comment_id: comment_id, content: content},
        %{context: %{auth: %{current_user: user}}}
      ) do
    Comment.update(comment_id, user.id, content)
  end

  def delete_comment(
        _root,
        %{comment_id: comment_id},
        %{context: %{auth: %{current_user: user}}}
      ) do
    Comment.delete(comment_id, user.id)
  end

  # Comments inherit the visibility of their entity: private entities' comments
  # are readable only by the entity owner (see EntityComment.get_comments/4).
  def comments(_root, %{entity_type: entity_type} = args, resolution) do
    comments =
      EntityComment.get_comments(
        entity_type,
        Map.get(args, :id),
        args,
        current_user_id(resolution)
      )
      |> Enum.map(& &1.comment)

    {:ok, comments}
  end

  def subcomments(_root, %{comment_id: comment_id, limit: limit}, resolution) do
    with {:ok, comment_id} <- Sanbase.Utils.EctoCommon.cast_id(comment_id),
         {entity_type, entity_id} <- EntityComment.entity_of_comment(comment_id),
         true <-
           EntityComment.can_read_comments?(entity_type, entity_id, current_user_id(resolution)) do
      {:ok, Comment.get_subcomments(comment_id, limit)}
    else
      _ -> {:ok, []}
    end
  end

  defp current_user_id(%{context: %{auth: %{current_user: %{id: user_id}}}}), do: user_id
  defp current_user_id(_resolution), do: nil

  def comments_feed(
        _root,
        args,
        _resolution
      ) do
    comments = EntityComment.get_comments(args)

    {:ok, comments}
  end
end
