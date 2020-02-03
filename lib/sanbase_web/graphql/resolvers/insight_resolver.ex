defmodule SanbaseWeb.Graphql.Resolvers.InsightResolver do
  require Logger

  import Absinthe.Resolution.Helpers, except: [async: 1]

  alias SanbaseWeb.Graphql.SanbaseDataloader
  alias Sanbase.Auth.User
  alias Sanbase.Vote
  alias Sanbase.Insight.Post
  alias Sanbase.Comment.EntityComment
  alias Sanbase.Repo
  alias SanbaseWeb.Graphql.Helpers.Utils

  require Logger

  def insights(%User{} = user, _args, _resolution) do
    {:ok, Post.user_insights(user.id)}
  end

  def public_insights(%User{} = user, _args, _resolution) do
    {:ok, Post.user_public_insights(user.id)}
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
    {:ok, Sanbase.Tag.all()}
  end

  @doc ~s"""
    Returns a tuple `{total_votes, total_san_votes}` where:
    - `total_votes` represents the number of votes where each vote's weight is 1
    - `total_san_votes` represents the number of votes where each vote's weight is
    equal to the san balance of the voter
  """
  def votes(%Post{} = post, _args, _context) do
    {total_votes, total_san_votes} =
      post
      |> Repo.preload(votes: [user: :eth_accounts])
      |> Map.get(:votes)
      |> Stream.map(&Map.get(&1, :user))
      |> Stream.map(&User.san_balance!/1)
      |> Enum.reduce({0, 0}, fn san_balance, {votes, san_token_votes} ->
        {votes + 1, san_token_votes + san_balance}
      end)

    {:ok,
     %{
       total_votes: total_votes,
       total_san_votes: total_san_votes |> Sanbase.Math.to_integer()
     }}
  end

  def voted_at(%Post{} = post, _args, %{
        context: %{auth: %{current_user: user}}
      }) do
    post
    |> Repo.preload([:votes])
    |> Map.get(:votes, [])
    |> Enum.find(&(&1.user_id == user.id))
    |> case do
      nil -> {:ok, nil}
      vote -> {:ok, vote.inserted_at}
    end
  end

  def voted_at(%Post{}, _args, _context), do: {:ok, nil}

  def vote(_root, args, %{
        context: %{auth: %{current_user: user}}
      }) do
    insight_id = Map.get(args, :insight_id) || Map.fetch!(args, :post_id)

    Vote.create(%{post_id: insight_id, user_id: user.id})
    |> case do
      {:ok, _vote} ->
        Post.by_id(insight_id)

      {:error, changeset} ->
        {
          :error,
          message: "Can't vote for post with id #{insight_id}",
          details: Utils.error_details(changeset)
        }
    end
  end

  def unvote(_root, args, %{
        context: %{auth: %{current_user: user}}
      }) do
    insight_id = Map.get(args, :insight_id) || Map.fetch!(args, :post_id)

    with %Vote{} = vote <- Vote.get_by_opts(post_id: insight_id, user_id: user.id),
         {:ok, _vote} <- Vote.remove(vote) do
      Post.by_id(insight_id)
    else
      _error ->
        {:error, "Can't remove vote for post with id #{insight_id}"}
    end
  end

  # Note: deprecated - should be removed if not used by frontend
  def insight_comments(
        _root,
        %{insight_id: post_id} = args,
        _resolution
      ) do
    comments =
      EntityComment.get_comments(:insight, post_id, args)
      |> Enum.map(& &1.comment)

    {:ok, comments}
  end

  def insight_id(%{id: id}, _args, %{context: %{loader: loader}}) do
    loader
    |> Dataloader.load(SanbaseDataloader, :comment_insight_id, id)
    |> on_load(fn loader ->
      {:ok, Dataloader.get(loader, SanbaseDataloader, :comment_insight_id, id)}
    end)
  end

  def comments_count(%{id: id}, _args, %{context: %{loader: loader}}) do
    loader
    |> Dataloader.load(SanbaseDataloader, :insights_comments_count, id)
    |> on_load(fn loader ->
      {:ok, Dataloader.get(loader, SanbaseDataloader, :insights_comments_count, id) || 0}
    end)
  end
end
