defmodule SanbaseWeb.Graphql.Resolvers.InsightResolver do
  import Absinthe.Resolution.Helpers, except: [async: 1]

  alias SanbaseWeb.Graphql.SanbaseDataloader
  alias Sanbase.Accounts.User
  alias Sanbase.Insight.Post
  alias Sanbase.Insights
  alias Sanbase.Comments.EntityComment

  @list_opt_keys [:is_pulse, :is_paywall_required, :from, :to]
  @list_opt_keys_with_categories [:is_pulse, :is_paywall_required, :categories, :from, :to]

  def popular_insight_authors(_root, _args, _resolution), do: Insights.popular_authors()

  def insights(%User{} = user, %{page: page, page_size: page_size} = args, _resolution) do
    {:ok, Insights.user_insights(user.id, list_opts(args, page, page_size))}
  end

  def public_insights(%User{} = user, %{page: page, page_size: page_size} = args, _resolution) do
    {:ok, Insights.user_public_insights(user.id, list_opts(args, page, page_size))}
  end

  def related_projects(%Post{} = post, _, _), do: Insights.related_projects(post)

  def post(_root, %{id: post_id}, %{context: context}) do
    viewer_id = get_in(context, [:auth, :current_user, Access.key(:id)])
    Insights.get_post(post_id, viewer_id)
  end

  def all_insights(_root, %{tags: tags, page: page, page_size: page_size} = args, _context)
      when is_list(tags) do
    {:ok, Insights.public_insights_by_tags(tags, list_opts(args, page, page_size, :categories))}
  end

  def all_insights(_root, %{page: page, page_size: page_size} = args, _resolution) do
    {:ok, Insights.public_insights(list_opts(args, page, page_size, :categories))}
  end

  def all_insights_for_user(
        _root,
        %{user_id: user_id, page: page, page_size: page_size} = args,
        _context
      ) do
    {:ok, Insights.user_public_insights(user_id, list_opts(args, page, page_size, :categories))}
  end

  def all_insights_user_voted_for(_root, %{user_id: user_id} = args, _context) do
    {:ok, Insights.user_voted_insights(user_id, list_opts(args))}
  end

  def all_insights_by_tag(_root, %{tag: tag} = args, _context) do
    {:ok, Insights.public_insights_by_tags([tag], list_opts(args))}
  end

  def all_insights_by_search_term(
        _root,
        %{search_term: search_term, page: page, page_size: page_size} = args,
        _context
      ) do
    {:ok, Insights.search_published(search_term, list_opts(args, page, page_size))}
  end

  def pulse_text(%Post{} = post, _args, _resolution), do: Insights.pulse_text(post)

  def create_post(_root, args, %{context: %{auth: %{current_user: user}}}),
    do: Insights.create_post(user, args)

  def update_post(_root, %{id: post_id} = args, %{
        context: %{auth: %{current_user: %User{} = user}}
      }),
      do: Insights.update_post(post_id, user, args)

  def delete_post(_root, %{id: post_id}, %{
        context: %{auth: %{current_user: %User{} = user}}
      }),
      do: Insights.delete_post(post_id, user)

  def publish_insight(_root, %{id: post_id}, %{
        context: %{auth: %{current_user: %User{id: user_id}}}
      }),
      do: Insights.publish(post_id, user_id)

  def all_tags(_root, _args, _context), do: {:ok, Insights.all_tags()}

  def all_insight_categories(_root, _args, _context), do: Insights.all_categories_with_count()

  def post_categories(%Post{id: id}, _args, %{context: %{loader: loader}}) do
    loader
    |> Dataloader.load(SanbaseDataloader, :post_categories, id)
    |> on_load(fn loader ->
      categories =
        Dataloader.get(loader, SanbaseDataloader, :post_categories, id)
        |> List.wrap()
        |> Enum.map(fn %{category_name: name} -> %{name: name} end)

      {:ok, categories}
    end)
  end

  def resolve_images(%Post{} = post, _args, _resolution), do: Insights.resolve_post_images(post)

  def insights_count(%User{id: id}, _args, %{context: %{loader: loader}}) do
    loader
    |> Dataloader.load(SanbaseDataloader, :insights_count_per_user, id)
    |> on_load(fn loader ->
      count =
        Dataloader.get(loader, SanbaseDataloader, :insights_count_per_user, id) ||
          Insights.empty_insights_count()

      {:ok, count}
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

  def create_chart_event(_root, args, %{context: %{auth: %{current_user: user}}}),
    do: Insights.create_chart_event(user.id, args)

  defp list_opts(args, page, page_size, :categories) do
    args
    |> Map.take(@list_opt_keys_with_categories)
    |> Map.to_list()
    |> Keyword.merge(page: page, page_size: page_size)
  end

  defp list_opts(args, page, page_size) do
    args
    |> Map.take(@list_opt_keys)
    |> Map.to_list()
    |> Keyword.merge(page: page, page_size: page_size)
  end

  defp list_opts(args), do: args |> Map.take(@list_opt_keys) |> Map.to_list()
end
