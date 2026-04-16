defmodule SanbaseWeb.Graphql.Resolvers.InsightResolver do
  import Absinthe.Resolution.Helpers, except: [async: 1]

  alias SanbaseWeb.Graphql.SanbaseDataloader
  alias Sanbase.Accounts.User
  alias Sanbase.Insight.Post
  alias Sanbase.Insight.PostImage
  alias Sanbase.Insight.ImageUrl
  alias Sanbase.Insight.PopularAuthor
  alias Sanbase.Comments.EntityComment

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

  def post(_root, %{id: post_id}, %{context: context} = _resolution) do
    user = get_in(context, [:auth, :current_user]) || %User{id: nil}
    user_id = user.id

    case Post.by_id(post_id, []) do
      {:ok, %Post{state: "approved", ready_state: "published"} = post} ->
        {:ok, post}

      {:ok, %Post{user_id: ^user_id} = post} ->
        {:ok, post}

      {:ok, _} ->
        {:error,
         "Insight with id #{post_id} does not exist, is not published, or is not approved"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def all_insights(_root, %{tags: tags, page: page, page_size: page_size} = args, _context)
      when is_list(tags) do
    opts = [
      is_pulse: Map.get(args, :is_pulse),
      is_paywall_required: Map.get(args, :is_paywall_required),
      categories: Map.get(args, :categories),
      from: Map.get(args, :from),
      to: Map.get(args, :to),
      page: page,
      page_size: page_size
    ]

    posts = Post.public_insights_by_tags(tags, opts)

    {:ok, posts}
  end

  def all_insights(_root, %{page: page, page_size: page_size} = args, _resolution) do
    opts = [
      is_pulse: Map.get(args, :is_pulse),
      is_paywall_required: Map.get(args, :is_paywall_required),
      categories: Map.get(args, :categories),
      from: Map.get(args, :from),
      to: Map.get(args, :to),
      page: page,
      page_size: page_size
    ]

    posts = Post.public_insights(opts)

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
      categories: Map.get(args, :categories),
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

  def all_insights_by_search_term(
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
    search_result_insights = Post.search_published_insights(search_term, opts)

    {:ok, search_result_insights}
  end

  @doc ~s"""
  When fetching all insights we need to directly show only the text of the pulse insights.
  In order to transport less data over the network, this field can be used instead of
  the `text` field as it will be filled only for those insights.
  """
  def pulse_text(%Post{} = post, _args, _resolution) do
    case Post.pulse?(post) do
      true -> {:ok, post.text}
      _ -> {:ok, nil}
    end
  end

  def create_post(_root, args, %{context: %{auth: %{current_user: user}}}) do
    case Post.has_not_reached_rate_limits?(user.id) do
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

  @doc "Returns all insight categories with the count of published insights in each."
  @spec all_insight_categories(any(), map(), any()) :: {:ok, list(map())}
  def all_insight_categories(_root, _args, _context) do
    Sanbase.Insight.Category.all_with_insight_count()
  end

  @doc "Returns the categories assigned to a given post via dataloader."
  @spec post_categories(%Post{}, map(), Absinthe.Resolution.t()) :: any()
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

  @doc """
  Resolve images for an insight by combining DB-linked images with
  regex-extracted images from text. This ensures backward compatibility
  for old insights where images were never properly linked in the DB.
  """
  def resolve_images(%Post{text: text, images: images}, _args, _resolution) do
    db_images =
      case images do
        images when is_list(images) ->
          Enum.map(images, &post_image_to_map/1)

        _ ->
          []
      end

    regex_images =
      ImageUrl.extract_from_text(text)
      |> Enum.map(fn url -> %{image_url: url} end)

    all_images =
      (db_images ++ regex_images)
      |> Enum.uniq_by(fn %{image_url: url} -> url end)

    {:ok, all_images}
  end

  defp post_image_to_map(%PostImage{} = image) do
    %{
      image_url: image.image_url,
      image_url_w400: image.image_url_w400,
      image_url_w800: image.image_url_w800,
      image_url_w1200: image.image_url_w1200,
      image_url_w2000: image.image_url_w2000
    }
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
