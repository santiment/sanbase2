defmodule SanbaseWeb.Graphql.Resolvers.InsightResolver do
  require Logger

  import Absinthe.Resolution.Helpers, except: [async: 1]

  alias SanbaseWeb.Graphql.SanbaseDataloader
  alias Sanbase.Auth.User
  alias Sanbase.Vote
  alias Sanbase.Insight.Post
  alias Sanbase.Comments.EntityComment
  alias SanbaseWeb.Graphql.Helpers.Utils

  require Logger

  def insights(%User{} = user, args, _resolution) do
    opts = [
      is_pulse: Map.get(args, :is_pulse),
      is_paywall_required: Map.get(args, :is_paywall_required)
    ]

    {:ok, Post.user_insights(user.id, opts)}
  end

  def public_insights(%User{} = user, args, _resolution) do
    opts = [
      is_pulse: Map.get(args, :is_pulse),
      is_paywall_required: Map.get(args, :is_paywall_required)
    ]

    {:ok, Post.user_public_insights(user.id, opts)}
  end

  def related_projects(%Post{} = post, _, _) do
    Post.related_projects(post)
  end

  def post(_root, %{id: post_id}, _resolution) do
    Post.by_id(post_id)
  end

  def all_insights(_root, %{tags: tags, page: page, page_size: page_size} = args, _context)
      when is_list(tags) do
    opts = [
      is_pulse: Map.get(args, :is_pulse),
      is_paywall_required: Map.get(args, :is_paywall_required)
    ]

    posts = Post.public_insights_by_tags(tags, page, page_size, opts)

    {:ok, posts}
  end

  def all_insights(_root, %{page: page, page_size: page_size} = args, _resolution) do
    opts = [
      is_pulse: Map.get(args, :is_pulse),
      is_paywall_required: Map.get(args, :is_paywall_required)
    ]

    posts = Post.public_insights(page, page_size, opts)

    {:ok, posts}
  end

  def all_insights_for_user(_root, %{user_id: user_id} = args, _context) do
    opts = [
      is_pulse: Map.get(args, :is_pulse),
      is_paywall_required: Map.get(args, :is_paywall_required)
    ]

    posts = Post.user_public_insights(user_id, opts)

    {:ok, posts}
  end

  def all_insights_user_voted_for(_root, %{user_id: user_id} = args, _context) do
    opts = [
      is_pulse: Map.get(args, :is_pulse),
      is_paywall_required: Map.get(args, :is_paywall_required)
    ]

    posts = Post.all_insights_user_voted_for(user_id, opts)

    {:ok, posts}
  end

  def all_insights_by_tag(_root, %{tag: tag} = args, _context) do
    opts = [
      is_pulse: Map.get(args, :is_pulse),
      is_paywall_required: Map.get(args, :is_paywall_required)
    ]

    posts = Post.public_insights_by_tags([tag], opts)

    {:ok, posts}
  end

  def all_insights_by_search_term(_root, %{search_term: search_term} = args, _context) do
    opts = [
      is_pulse: Map.get(args, :is_pulse),
      is_paywall_required: Map.get(args, :is_paywall_required)
    ]

    # Search is done only on the publicly visible (published) insights.
    search_result_insights =
      Post.public_insights_query(opts)
      |> Sanbase.Insight.Search.run(search_term)

    {:ok, search_result_insights}
  end

  def create_post(_root, args, %{context: %{auth: %{current_user: user}}}) do
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
  def votes(%Post{} = post, _args, %{context: %{auth: %{current_user: user}}}) do
    {:ok, Vote.total_votes(post, user)}
  end

  def votes(%Post{} = post, _args, _context) do
    {:ok, Vote.total_votes(post)}
  end

  def voted_at(%Post{} = post, _args, %{context: %{auth: %{current_user: user}}}) do
    {:ok, Vote.voted_at(post, user)}
  end

  def voted_at(%Post{}, _args, _context), do: {:ok, nil}

  def vote(_root, args, %{context: %{auth: %{current_user: user}}}) do
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

  def unvote(_root, args, %{context: %{auth: %{current_user: user}}}) do
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
  def insight_comments(_root, %{insight_id: insight_id} = args, _resolution) do
    comments =
      EntityComment.get_comments(:insight, insight_id, args)
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

  def create_chart_event(_root, args, %{context: %{auth: %{current_user: user}}}) do
    Post.create_chart_event(user.id, args)
  end
end
