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

  def comments(
        _root,
        %{entity_type: entity_type, id: id} = args,
        _resolution
      ) do
    comments = EntityComment.get_comments(entity_type, id, args) |> Enum.map(& &1.comment)

    {:ok, comments}
  end

  def comments(
        _root,
        %{entity_type: entity_type} = args,
        _resolution
      ) do
    comments = EntityComment.get_comments(entity_type, nil, args) |> Enum.map(& &1.comment)

    {:ok, comments}
  end

  def subcomments(
        _root,
        %{comment_id: comment_id} = args,
        _resolution
      ) do
    {:ok, Comment.get_subcomments(comment_id, args)}
  end

  def comments_feed(
        _root,
        args,
        _resolution
      ) do
    comments = EntityComment.get_comments(args)

    {:ok, comments}
  end
end
