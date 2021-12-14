defmodule SanbaseWeb.Graphql.Resolvers.InsightResolver do
  require Logger

  import Absinthe.Resolution.Helpers, except: [async: 1]

  alias SanbaseWeb.Graphql.SanbaseDataloader
  alias Sanbase.Accounts.User
  alias Sanbase.Insight.{Post, PopularAuthor}
  alias Sanbase.Comments.EntityComment

  require Logger

  def popular_insight_authors(_root, _args, _resolution) do
    PopularAuthor.get()
  end

  def insights(%User{} = user, %{page: page, page_size: page_size} = args, _resolution) do
    opts = [
      is_pulse: Map.get(args, :is_pulse),
      is_paywall_required: Map.get(args, :is_paywall_required),
      from: Map.get(args, :from),
      to: Map.get(args, :to),
      page: page,
      page_size: page_size
    ]

    {:ok, Post.user_insights(user.id, opts)}
  end

  def public_insights(%User{} = user, %{page: page, page_size: page_size} = args, _resolution) do
    opts = [
      is_pulse: Map.get(args, :is_pulse),
      is_paywall_required: Map.get(args, :is_paywall_required),
      from: Map.get(args, :from),
      to: Map.get(args, :to),
      page: page,
      page_size: page_size
    ]

    {:ok, Post.user_public_insights(user.id, opts)}
  end

  def related_projects(%Post{} = post, _, _) do
    Post.related_projects(post)
  end

  def post(_root, %{id: post_id}, _resolution) do
    Post.by_id(post_id, [])
  end

  def all_insights(_root, %{tags: tags, page: page, page_size: page_size} = args, _context)
      when is_list(tags) do
    opts = [
      is_pulse: Map.get(args, :is_pulse),
      is_paywall_required: Map.get(args, :is_paywall_required),
      from: Map.get(args, :from),
      to: Map.get(args, :to)
    ]

    posts = Post.public_insights_by_tags(tags, page, page_size, opts)

    {:ok, posts}
  end

  def all_insights(_root, %{page: page, page_size: page_size} = args, _resolution) do
    opts = [
      is_pulse: Map.get(args, :is_pulse),
      is_paywall_required: Map.get(args, :is_paywall_required),
      from: Map.get(args, :from),
      to: Map.get(args, :to)
    ]

    posts = Post.public_insights(page, page_size, opts)

    {:ok, posts}
  end

  def all_insights_for_user(
        _root,
        %{user_id: user_id, page: page, page_size: page_size} = args,
        _context
      ) do
    opts = [
      is_pulse: Map.get(args, :is_pulse),
      is_paywall_required: Map.get(args, :is_paywall_required),
      from: Map.get(args, :from),
      to: Map.get(args, :to),
      page: page,
      page_size: page_size
    ]

    posts = Post.user_public_insights(user_id, opts)

    {:ok, posts}
  end

  def all_insights_user_voted_for(_root, %{user_id: user_id} = args, _context) do
    opts = [
      is_pulse: Map.get(args, :is_pulse),
      is_paywall_required: Map.get(args, :is_paywall_required),
      from: Map.get(args, :from),
      to: Map.get(args, :to)
    ]

    posts = Post.all_insights_user_voted_for(user_id, opts)

    {:ok, posts}
  end

  def all_insights_by_tag(_root, %{tag: tag} = args, _context) do
    opts = [
      is_pulse: Map.get(args, :is_pulse),
      is_paywall_required: Map.get(args, :is_paywall_required),
      from: Map.get(args, :from),
      to: Map.get(args, :to)
    ]

    posts = Post.public_insights_by_tags([tag], opts)

    {:ok, posts}
  end

  def all_insights_by_search_term(_root, %{search_term: search_term} = args, _context) do
    opts = [
      is_pulse: Map.get(args, :is_pulse),
      is_paywall_required: Map.get(args, :is_paywall_required),
      from: Map.get(args, :from),
      to: Map.get(args, :to)
    ]

    # Search is done only on the publicly visible (published) insights.
    search_result_insights = Post.search_published_insights(search_term, opts)

    {:ok, search_result_insights}
  end

  def all_insights_by_search_term_highlighted(
        _root,
        %{search_term: search_term, page: page, page_size: page_size} = args,
        _context
      ) do
    opts = [
      is_pulse: Map.get(args, :is_pulse),
      is_paywall_required: Map.get(args, :is_paywall_required),
      from: Map.get(args, :from),
      to: Map.get(args, :to),
      page: page,
      page_size: page_size
    ]

    # Search is done only on the publicly visible (published) insights.
    search_result_insights = Post.search_published_insights_highglight(search_term, opts)

    {:ok, search_result_insights}
  end

  def create_post(_root, args, %{context: %{auth: %{current_user: user}}}) do
    case Post.can_create?(user.id) do
      {:ok, _} -> Post.create(user, args)
      {:error, error} -> {:error, error}
    end
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

  def insights_count(%User{id: id}, _args, %{context: %{loader: loader}}) do
    loader
    |> Dataloader.load(SanbaseDataloader, :insights_count_per_user, id)
    |> on_load(fn loader ->
      {:ok,
       Dataloader.get(loader, SanbaseDataloader, :insights_count_per_user, id) ||
         %{total_count: 0, draft_count: 0, pulse_count: 0, paywall_count: 0}}
    end)
  end

  # Note: deprecated - should be removed if not used by frontend
  def insight_comments(_root, %{insight_id: insight_id} = args, _resolution) do
    comments =
      EntityComment.get_comments(:insight, insight_id, args)
      |> Enum.map(& &1.comment)

    {:ok, comments}
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
