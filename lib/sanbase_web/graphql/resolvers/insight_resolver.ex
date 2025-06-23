defmodule SanbaseWeb.Graphql.Resolvers.InsightResolver do
  require Logger

  import Absinthe.Resolution.Helpers, except: [async: 1]

  alias SanbaseWeb.Graphql.SanbaseDataloader
  alias Sanbase.Accounts.User
  alias Sanbase.Insight.Post
  alias Sanbase.Insight.PopularAuthor
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

  case Application.compile_env(:sanbase, :env) do
    :test ->
      # In test env our file store stores images not in S3, but in /tmp
      defp image_url_regex() do
        storage_dir = Application.get_env(:waffle, :storage_dir)

        # Properly append / at the end otherwise compiled regex wont' be  proper
        storage_dir =
          if String.last(storage_dir) != "/", do: storage_dir <> "/", else: storage_dir

        Regex.compile!(~s{#{storage_dir}[^\s"<>]+(?:\.jpg|\.png|\.gif|\.jpeg)})
      end

    _ ->
      defp image_url_regex(),
        do:
          ~r{https://[a-zA-Z0-9\-\.]*sanbase-images.s3\.amazonaws\.com/[^\s"<>]+(?:\.jpg|\.png|\.gif|\.jpeg)}
  end

  defp image_url_regex() do
    ~r{https://[a-zA-Z0-9\-\.]*sanbase-images.s3\.amazonaws\.com/[^\s"<>]+(?:\.jpg|\.png|\.gif|\.jpeg)}
  end

  def extract_images_from_text(%Post{text: text}, _args, _resolution) do
    image_urls =
      Regex.scan(image_url_regex(), text)
      |> Enum.map(fn [url] -> url end)

    {:ok, Enum.map(image_urls, fn image_url -> %{image_url: image_url} end)}
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
