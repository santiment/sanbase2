defmodule SanbaseWeb.Graphql.Resolvers.InsightResolver do
  import Absinthe.Resolution.Helpers, except: [async: 1]

  alias SanbaseWeb.Graphql.SanbaseDataloader
  alias Sanbase.Accounts.User
  alias Sanbase.Insight.Post
  alias Sanbase.Insights

  @list_opt_keys [:is_pulse, :is_paywall_required, :from, :to]

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

  @doc ~s"""
  When fetching all insights we need to directly show only the text of the pulse insights.
  In order to transport less data over the network, this field can be used instead of
  the `text` field as it will be filled only for those insights.
  """
  def pulse_text(%Post{} = post, _args, resolution) do
    case Post.pulse?(post) do
      true -> paywalled_text(post, resolution)
      _ -> {:ok, nil}
    end
  end

  @doc ~s"""
  Paywalled insights are shown in full only to their author and to users whose
  plan can access them. This is applied on the field so every query that
  returns insights is covered.
  """
  def text(%Post{} = post, _args, resolution), do: paywalled_text(post, resolution)

  defp paywalled_text(%Post{is_paywall_required: true} = post, resolution) do
    batch_paywalled_texts(post, resolution, fn texts ->
      {text, _full_access?} = Map.fetch!(texts, post.id)
      {:ok, text}
    end)
  end

  defp paywalled_text(%Post{text: text}, _resolution), do: {:ok, text}

  # Batched, so the user's access to paywalled insights is checked once per
  # response instead of once per insight.
  defp batch_paywalled_texts(%Post{} = post, resolution, fun) do
    batch_arg = {resolution.context[:auth], exempt_author?(resolution)}

    batch({__MODULE__, :paywalled_texts, batch_arg}, post, fun)
  end

  # Authors see their own paywalled insights in full, except in responses stored in
  # the document cache (getMostRecent, getMostVoted, the project lists). That cache
  # has no user in its key, so there the paywall applies to the author as well.
  # Fetching only the user's own entities sets :do_not_cache_query and is not stored.
  defp exempt_author?(resolution) do
    not Map.has_key?(resolution.context, :query_cache_key) or
      Process.get(:do_not_cache_query) == true
  end

  @doc false
  def paywalled_texts({auth, exempt_author?}, posts) do
    posts
    |> Enum.uniq_by(& &1.id)
    |> Insights.filter_paywalled_with_access(auth, exempt_author: exempt_author?)
    |> Map.new(fn {post, full_access?} -> {post.id, {post.text, full_access?}} end)
  end

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

  def resolve_images(%Post{is_paywall_required: true} = post, _args, resolution) do
    # A viewer who gets only the preview text gets only the images in it. Batched
    # with the text field, so access is checked once per response.
    batch_paywalled_texts(post, resolution, fn texts ->
      {text, full_access?} = Map.fetch!(texts, post.id)
      {:ok, Insights.post_images(post, text, full_access?)}
    end)
  end

  def resolve_images(%Post{text: text} = post, _args, _resolution),
    do: {:ok, Insights.post_images(post, text, true)}

  def insights_count(%User{id: id}, _args, %{context: %{loader: loader}}) do
    loader
    |> Dataloader.load(SanbaseDataloader, :insights_count_per_user, id)
    |> on_load(fn loader ->
      {:ok,
       Dataloader.get(loader, SanbaseDataloader, :insights_count_per_user, id) ||
         %{total_count: 0, draft_count: 0, pulse_count: 0, paywall_count: 0}}
    end)
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

  defp list_opts(args, page, page_size, extra_keys \\ [])

  defp list_opts(args, page, page_size, :categories),
    do: list_opts(args, page, page_size, [:categories])

  defp list_opts(args, page, page_size, extra_keys) when is_list(extra_keys) do
    args
    |> Map.take(@list_opt_keys ++ extra_keys)
    |> Map.to_list()
    |> Keyword.merge(page: page, page_size: page_size)
  end

  defp list_opts(args), do: args |> Map.take(@list_opt_keys) |> Map.to_list()
end
