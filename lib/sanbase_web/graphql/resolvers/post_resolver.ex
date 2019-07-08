defmodule SanbaseWeb.Graphql.Resolvers.PostResolver do
  require Logger

  alias Sanbase.Auth.User
  alias Sanbase.Tag
  alias Sanbase.Insight.Post

  def insights(%User{} = user, _args, _resolution) do
    posts = Post.user_insights(user.id)

    {:ok, posts}
  end

  def related_projects(%Post{} = post, _, _) do
    Post.related_projects(post)
  end

  def post(_root, %{id: post_id}, _resolution) do
    Post.by_id(post_id)
  end

  def all_insights(_root, %{tags: tags, page: page, page_size: page_size}, _context)
      when is_list(tags) do
    posts = Post.public_insights_by_tags(tags, page, page_size)

    {:ok, posts}
  end

  def all_insights(_root, %{page: page, page_size: page_size}, _resolution) do
    posts = Post.public_insights(page, page_size)

    {:ok, posts}
  end

  def all_insights_for_user(_root, %{user_id: user_id}, _context) do
    posts = Post.user_public_insights(user_id)

    {:ok, posts}
  end

  def all_insights_user_voted_for(_root, %{user_id: user_id}, _context) do
    posts = Post.all_insights_user_voted_for(user_id)

    {:ok, posts}
  end

  def all_insights_by_tag(_root, %{tag: tag}, _context) do
    posts = Post.public_insights_by_tag(tag)

    {:ok, posts}
  end

  def create_post(_root, args, %{
        context: %{auth: %{current_user: user}}
      }) do
    Post.create(user, args)
  end

  def update_post(_root, %{id: post_id} = args, %{
        context: %{auth: %{current_user: %User{} = user}}
      }) do
    Post.update(post_id, user, args)
  end

  def delete_post(_root, %{id: post_id}, %{
        context: %{auth: %{current_user: %User{} = user}}
      }) do
    Post.delete(post_id, user)
  end

  def publish_insight(_root, %{id: post_id}, %{
        context: %{auth: %{current_user: %User{id: user_id}}}
      }) do
    Post.publish(post_id, user_id)
  end

  def all_tags(_root, _args, _context) do
    {:ok, Tag.all()}
  end
end
