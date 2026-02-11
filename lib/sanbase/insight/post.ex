defmodule Sanbase.Insight.Post do
  @behaviour Sanbase.Entity.Behaviour

  use Ecto.Schema

  import Ecto.Query
  import Ecto.Changeset
  import Sanbase.Insight.EventEmitter, only: [emit_event: 3]
  import Sanbase.Utils.ErrorHandling, only: [changeset_errors: 1]
  import Sanbase.Utils.Transform, only: [to_bang: 1]

  alias Sanbase.Tag
  alias Sanbase.Repo
  alias Sanbase.Accounts.User
  alias Sanbase.Project
  alias Sanbase.Insight.{Post, PostImage, Category}
  alias Sanbase.Timeline.TimelineEvent
  alias Sanbase.Metric.MetricPostgresData
  alias Sanbase.Chart.Configuration
  alias Sanbase.Utils.Config
  alias Sanbase.Insight.PostEmbedding

  require Logger

  @preloads [:user, :featured_item, :images, :tags, :chart_configuration_for_event]

  # state can be changed by moderators
  @awaiting_approval "awaiting_approval"
  @approved "approved"
  @declined "declined"
  @states [@awaiting_approval, @approved, @declined]
  def states(), do: @states

  # ready_state indicates whether the user has published the post or not
  @draft "draft"
  @published "published"
  @ready_states [@draft, @published]
  def ready_states(), do: @ready_states

  # predictions
  @predictions [
    "heavy_bullish",
    "semi_bullish",
    "semi_bearish",
    "heavy_bearish",
    "unspecified",
    "none"
  ]
  def predictions(), do: @predictions

  @type option ::
          {:is_pulse, boolean() | nil}
          | {:is_paywall_required, boolean() | nil}
          | {:from, DateTime.t() | nil}
          | {:to, DateTime.t() | nil}
          | {:page, non_neg_integer()}
          | {:page_size, non_neg_integer()}

  @type opts :: [option]

  schema "posts" do
    field(:title, :string)
    field(:short_desc, :string)
    field(:text, :string)
    field(:is_deleted, :boolean, default: false)
    field(:is_hidden, :boolean, default: false)
    field(:state, :string, default: @approved)
    field(:moderation_comment, :string)
    field(:ready_state, :string, default: @draft)
    field(:is_pulse, :boolean, default: false)
    field(:is_paywall_required, :boolean, default: false)
    field(:prediction, :string, default: "unspecified")

    # Chart events are insights connected to specific chart configuration and datetime
    field(:is_chart_event, :boolean, default: false)
    field(:chart_event_datetime, :utc_datetime)

    belongs_to(:user, User)
    belongs_to(:chart_configuration_for_event, Configuration)
    belongs_to(:price_chart_project, Project)

    has_one(:featured_item, Sanbase.FeaturedItem, on_delete: :delete_all)

    has_many(:embeddings, PostEmbedding)

    has_many(:chart_configurations, Configuration)
    has_many(:images, PostImage, on_delete: :delete_all)
    has_many(:timeline_events, TimelineEvent, on_delete: :delete_all)
    has_many(:votes, Sanbase.Vote, on_delete: :delete_all)

    many_to_many(:tags, Tag,
      join_through: "posts_tags",
      on_replace: :delete,
      on_delete: :delete_all
    )

    has_many(:comments, Sanbase.Comment.PostComment)

    many_to_many(:metrics, MetricPostgresData,
      join_through: "posts_metrics",
      join_keys: [post_id: :id, metric_id: :id],
      on_replace: :delete,
      on_delete: :delete_all
    )

    many_to_many(:categories, Category,
      join_through: "insight_category_mapping",
      on_replace: :delete
    )

    field(:published_at, :naive_datetime)

    # Virtual fields
    field(:views, :integer, virtual: true, default: 0)
    field(:is_featured, :boolean, virtual: true)

    timestamps()
  end

  def find_most_similar_insight_chunks(user_input, size \\ 3)

  def find_most_similar_insight_chunks(user_input, size) when is_binary(user_input) do
    with {:ok, [user_embedding]} <-
           Sanbase.AI.Embedding.generate_embeddings([user_input], 1536) do
      find_most_similar_insight_chunks(user_embedding, size)
    end
  end

  def find_most_similar_insight_chunks(embedding, size) when is_list(embedding) do
    query =
      from(
        e in PostEmbedding,
        inner_join: p in Post,
        on: e.post_id == p.id,
        select: %{
          post_id: e.post_id,
          post_title: p.title,
          text_chunk: e.text_chunk,
          similarity: fragment("1 - (embedding <=> ?)", ^embedding)
        },
        order_by: [desc: fragment("1 - (embedding <=> ?)", ^embedding)],
        limit: ^size
      )

    result = Sanbase.Repo.all(query)
    {:ok, result}
  end

  def find_most_similar_insights(embedding, size) when is_list(embedding) do
    query =
      from(
        e in PostEmbedding,
        inner_join: p in Post,
        on: e.post_id == p.id,
        where: p.ready_state == ^@published and p.state == ^@approved and p.is_deleted != true,
        group_by: [e.post_id, p.title],
        select: %{
          post_id: e.post_id,
          post_title: p.title,
          similarity: fragment("MAX(1 - (embedding <=> ?))", ^embedding)
        },
        order_by: [desc: fragment("MAX(1 - (embedding <=> ?))", ^embedding)],
        limit: ^size
      )

    result = Sanbase.Repo.all(query)
    {:ok, result}
  end

  @doc ~s"""
  Builds an Ecto query that finds insights similar to the given embedding vector.

  The query joins PostEmbedding with Post, filters by entity_ids_query, groups by post_id,
  and calculates similarity scores using the cosine distance operator (<=>).

  ## Parameters

    * `embedding` - A list of floats representing the embedding vector (typically 1536 dimensions)
    * `entity_ids_query` - An Ecto query that returns post IDs to filter by
    * `opts` - Keyword list of options:
      * `:limit` - Maximum number of results to return (default: 1000)

  ## Returns

    An Ecto query that can be executed to get insights with similarity scores.

  ## Example

      iex> embedding = List.duplicate(0.1, 1536)
      iex> entity_ids_query = from(p in Post, where: p.ready_state == "published", select: p.id)
      iex> query = Post.similar_insights_query(embedding, entity_ids_query, limit: 10)
      iex> Sanbase.Repo.all(query)
      [%{post_id: 1, similarity: 0.95}, ...]

  """
  @spec similar_insights_query([float()], Ecto.Query.t(), Keyword.t()) :: Ecto.Query.t()
  def similar_insights_query(embedding, entity_ids_query, opts \\ [])
      when is_list(embedding) do
    limit = Keyword.get(opts, :limit, 1000)

    from(
      e in PostEmbedding,
      inner_join: p in Post,
      on: e.post_id == p.id,
      where: p.id in subquery(entity_ids_query),
      group_by: [e.post_id],
      select: %{
        post_id: e.post_id,
        similarity: fragment("MAX(1 - (embedding <=> ?))", ^embedding)
      },
      order_by: [desc: fragment("MAX(1 - (embedding <=> ?))", ^embedding)],
      limit: ^limit
    )
  end

  def admin_keyword_search(search_term, opts \\ []) do
    page = Keyword.get(opts, :page, 1)
    page_size = Keyword.get(opts, :page_size, 50)
    sort_by = Keyword.get(opts, :sort_by, "published_at")
    sort_order = Keyword.get(opts, :sort_order, "desc")

    query =
      base_query()
      |> filter_published_and_approved()
      |> apply_keyword_filter(search_term)
      |> apply_admin_sort(sort_by, sort_order)

    total_count = Repo.aggregate(query, :count, :id)
    total_pages = max(1, div(total_count + page_size - 1, page_size))
    page = page |> max(1) |> min(total_pages)

    offset = (page - 1) * page_size

    posts =
      query
      |> limit(^page_size)
      |> offset(^offset)
      |> preload([:user, :categories])
      |> Repo.all()

    {posts, total_count, total_pages, page}
  end

  def admin_semantic_search(search_term, size \\ 50) do
    with {:ok, [embedding]} <- Sanbase.AI.Embedding.generate_embeddings([search_term], 1536),
         {:ok, results} <- find_most_similar_insights(embedding, size) do
      post_ids = Enum.map(results, & &1.post_id)

      if post_ids == [] do
        {[], 0}
      else
        posts =
          from(p in Post,
            where: p.id in ^post_ids,
            preload: [:user, :categories]
          )
          |> Repo.all()
          |> Enum.sort_by(fn post -> Enum.find_index(post_ids, &(&1 == post.id)) end)

        {posts, length(posts)}
      end
    else
      _ -> {[], 0}
    end
  end

  defp apply_keyword_filter(query, ""), do: query

  defp apply_keyword_filter(query, search_term) when is_binary(search_term) do
    search_pattern = "%#{search_term}%"

    from(
      p in query,
      where: ilike(p.title, ^search_pattern) or ilike(p.text, ^search_pattern)
    )
  end

  defp apply_admin_sort(query, sort_by, sort_order) do
    order_by_clause =
      case {sort_by, sort_order} do
        {"published_at", "asc"} -> [asc: :published_at]
        {"published_at", "desc"} -> [desc: :published_at]
        {"title", "asc"} -> [asc: :title]
        {"title", "desc"} -> [desc: :title]
        _ -> [desc: :published_at]
      end

    from(p in query, order_by: ^order_by_clause)
  end

  # The base of all the entity queries
  defp base_entity_ids_query(opts) do
    base_insights_query(opts)
    |> maybe_apply_projects_filter_query(opts)
    |> Sanbase.Entity.Query.maybe_filter_is_hidden(opts)
    |> Sanbase.Entity.Query.maybe_filter_is_featured_query(opts, :post_id)
    |> Sanbase.Entity.Query.maybe_filter_by_users(opts)
    |> Sanbase.Entity.Query.maybe_filter_by_cursor(:published_at, opts)
    |> Sanbase.Entity.Query.maybe_apply_public_status_and_private_access(opts)
    |> select([p], p.id)
  end

  @impl Sanbase.Entity.Behaviour
  def get_visibility_data(id) do
    query =
      from(entity in base_query(),
        where: entity.id == ^id,
        select: %{
          is_public: entity.state == ^@approved and entity.ready_state == ^@published,
          is_hidden: entity.is_hidden,
          user_id: entity.user_id
        }
      )

    case Repo.one(query) do
      %{} = map -> {:ok, map}
      nil -> {:error, "The dashboard with id #{id} does not exist"}
    end
  end

  @impl Sanbase.Entity.Behaviour
  def by_id!(id, opts), do: by_id(id, opts) |> to_bang()

  @impl Sanbase.Entity.Behaviour
  def by_id(id, opts) do
    result =
      base_insights_query(opts)
      |> Repo.get(id)

    case result do
      nil -> {:error, "There is no insight with id #{id}"}
      post -> {:ok, post}
    end
  end

  @impl Sanbase.Entity.Behaviour
  def by_ids!(ids, opts) when is_list(ids), do: by_ids(ids, opts) |> to_bang()

  @impl Sanbase.Entity.Behaviour
  def by_ids(post_ids, opts) when is_list(post_ids) do
    opts = Keyword.put_new(opts, :preload, @preloads)
    Sanbase.Entity.Query.by_ids_with_order(base_query(), post_ids, opts)
  end

  @impl Sanbase.Entity.Behaviour
  def public_and_user_entity_ids_query(user_id, opts) do
    base_entity_ids_query(opts)
    |> where(
      [p],
      (p.ready_state == ^@published and p.state == ^@approved) or p.user_id == ^user_id
    )
  end

  def entity_ids_by_opts(opts) do
    base_entity_ids_query(opts)
  end

  @impl Sanbase.Entity.Behaviour
  def public_entity_ids_query(opts) do
    base_entity_ids_query(opts)
    |> filter_published_and_approved()
  end

  @impl Sanbase.Entity.Behaviour
  def user_entity_ids_query(user_id, opts) do
    base_entity_ids_query(opts)
    |> by_user(user_id)
  end

  def insights_count_map() do
    map =
      from(
        p in __MODULE__,
        select: {
          p.user_id,
          fragment("COUNT(*) FILTER (WHERE ready_state = 'published') AS total_count"),
          fragment("COUNT(*) FILTER (WHERE ready_state = 'draft') AS draft_count"),
          fragment("COUNT(*) FILTER (WHERE is_pulse = true) AS pulse_count"),
          fragment("COUNT(*) FILTER (WHERE is_paywall_required = true) AS paywall_count")
        },
        group_by: p.user_id
      )
      |> Repo.all()
      |> Map.new(fn {user_id, total, draft, pulse, paywall} ->
        {user_id,
         %{
           total_count: total,
           draft_count: draft,
           pulse_count: pulse,
           paywall_count: paywall
         }}
      end)

    {:ok, map}
  end

  def has_not_reached_rate_limits?(user_id) do
    limits = %{
      day: Config.module_get(__MODULE__, :creation_limit_day, 20),
      hour: Config.module_get(__MODULE__, :creation_limit_hour, 10),
      minute: Config.module_get(__MODULE__, :creation_limit_minute, 3)
    }

    Sanbase.Ecto.Common.has_not_reached_rate_limits?(__MODULE__, user_id,
      limits: limits,
      entity_singular: "insight",
      entity_plural: "insights"
    )
  end

  def create_changeset(%Post{} = post, attrs) do
    attrs = Sanbase.DateTimeUtils.truncate_datetimes(attrs)

    post
    |> cast(attrs, [
      :title,
      :short_desc,
      :text,
      :user_id,
      :is_pulse,
      :is_paywall_required,
      :prediction,
      :price_chart_project_id,
      :is_chart_event,
      :chart_event_datetime,
      :chart_configuration_for_event_id,
      :ready_state
    ])
    |> Tag.put_tags(attrs)
    |> MetricPostgresData.put_metrics(attrs)
    |> images_cast(attrs)
    |> validate_required([:user_id, :title])
    |> validate_length(:title, max: 140)
  end

  def changeset(%Post{} = post, attrs) do
    # Do this so we can edit the post via the admin panel
    update_changeset(post, attrs)
  end

  def update_changeset(%Post{} = post, attrs) do
    attrs = Sanbase.DateTimeUtils.truncate_datetimes(attrs)

    preloads =
      if(attrs[:tags], do: [:tags], else: []) ++
        if attrs[:metrics], do: [:metrics], else: []

    post
    |> Repo.preload(preloads)
    |> cast(attrs, [
      :title,
      :short_desc,
      :text,
      :moderation_comment,
      :state,
      :ready_state,
      :is_pulse,
      :is_deleted,
      :is_hidden,
      :is_paywall_required,
      :prediction,
      :price_chart_project_id,
      :is_chart_event,
      :chart_event_datetime
    ])
    |> Tag.put_tags(attrs)
    |> MetricPostgresData.put_metrics(attrs)
    |> images_cast(attrs)
    |> validate_length(:title, max: 140)
    |> validate_change(:prediction, &valid_prediction?/2)
    |> maybe_add_updated_at()
  end

  def publish_changeset(%Post{} = post, attrs) do
    attrs = Sanbase.DateTimeUtils.truncate_datetimes(attrs)
    naive_now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    post
    |> cast(attrs, [:state, :ready_state, :published_at])
    |> change(published_at: naive_now)
  end

  def awaiting_approval_state(), do: @awaiting_approval
  def approved_state(), do: @approved
  def declined_state(), do: @declined
  def published(), do: @published
  def draft(), do: @draft
  def preloads(), do: @preloads

  def published?(%Post{ready_state: ready_state}),
    do: ready_state == @published

  @spec create(%User{}, map()) :: {:ok, %__MODULE__{}} | {:error, Keyword.t()}
  def create(%User{id: user_id}, args) do
    %__MODULE__{user_id: user_id}
    |> create_changeset(args)
    |> Repo.insert()
    |> case do
      {:ok, post} ->
        emit_event({:ok, post}, :create_insight, %{})
        :ok = Sanbase.Insight.Search.update_document_tokens(post.id)
        {:ok, post}

      {:error, changeset} ->
        {
          :error,
          message: "Cannot create insight", details: changeset_errors(changeset)
        }
    end
  end

  @spec update(non_neg_integer(), %User{}, map()) ::
          {:ok, %__MODULE__{}} | {:error, String.t()} | {:error, Keyword.t()}
  def update(post_id, %User{id: user_id}, args) do
    case by_id(post_id, preload?: false) do
      {:ok, %__MODULE__{user_id: ^user_id} = post} ->
        # If the tags are updated they need to be dropped from the mapping table
        # and inserted again as the order needs to be preserved.
        maybe_drop_post_tags(post, args)

        update_changeset =
          post
          |> Repo.preload([:tags, :images])
          |> update_changeset(args)

        case Repo.update(update_changeset) do
          {:ok, post} ->
            # Update the embeddings only if the title or text changed and the post is published.
            # On embed existing embeddings are deleted and the new one are created
            published? = post.ready_state == @published

            content_changed? =
              Map.has_key?(update_changeset.changes, :text) or
                Map.has_key?(update_changeset.changes, :title)

            if published? and content_changed? do
              async_embed_post(post)
            end

            emit_event({:ok, post}, :update_insight, %{})
            :ok = Sanbase.Insight.Search.update_document_tokens(post.id)
            {:ok, post}

          {:error, error} ->
            {:error, error}
        end

      {:ok, %__MODULE__{user_id: another_user_id}} when user_id != another_user_id ->
        {:error, "Cannot update not owned insight: #{post_id}"}

      {:error, error} ->
        {:error, error}
    end
  end

  @spec delete(non_neg_integer(), %User{}) ::
          {:ok, %__MODULE__{}} | {:error, String.t()} | {:error, Keyword.t()}
  def delete(post_id, %User{id: user_id}) do
    case by_id(post_id, preload?: false) do
      {:ok, %__MODULE__{user_id: ^user_id} = post} ->
        # Delete the images from the S3/Local store.
        delete_post_images(post)

        # Note: When ecto changeset middleware is implemented return just `Repo.delete(post)`
        case Repo.delete(post) do
          {:ok, post} ->
            emit_event({:ok, post}, :delete_insight, %{})

            {:ok, post}

          {:error, changeset} ->
            {:error,
             message: "Cannot delete post with id #{post_id}",
             details: changeset_errors(changeset)}
        end

      _post ->
        {:error, "Post with id #{post_id} does not exist or it's not yours"}
    end
  end

  def publish(post_id, user_id) do
    post_id = Sanbase.Math.to_integer(post_id)

    with {:ok, post} <- by_id(post_id, preload?: true, preload: [:user]),
         %Post{user_id: ^user_id, ready_state: @draft} <- post,
         {:ok, post} <- publish_post(post) do
      emit_event({:ok, post}, :publish_insight, %{})
      post = post |> Repo.preload(@preloads)

      {:ok, post}
    else
      %Post{user_id: id} when id != user_id ->
        {:error, "Cannot publish not own insight with id: #{post_id}"}

      %Post{ready_state: ready_state} when ready_state != @draft ->
        {:error, "Cannot publish already published insight with id: #{post_id}"}

      {:error, error} ->
        error_message = "Cannot publish insight with id #{post_id}"
        Logger.info("#{error_message}. Reason: #{inspect(error)}")
        {:error, error_message}
    end
  end

  def unpublish(post_id) do
    post_id = Sanbase.Math.to_integer(post_id)

    with {:ok, post} <- by_id(post_id, preload?: false),
         %Post{ready_state: @published} <- post,
         {:ok, post} <- unpublish_post(post) do
      # Delete embeddings
      Sanbase.Insight.PostEmbedding.drop_post_embeddings(post)

      emit_event({:ok, post}, :unpublish_insight, %{})
      post = post |> Repo.preload(@preloads)

      {:ok, post}
    else
      %Post{ready_state: ready_state} when ready_state != @published ->
        {:error, "Cannot unpublish a draft insight with id: #{post_id}"}

      {:error, error} ->
        error_message = "Cannot unpublish insight with id #{post_id}"
        Logger.error("#{error_message}. Reason: #{inspect(error)}")
        {:error, error_message}
    end
  end

  @spec search_published_insights(String.t(), opts) :: [%__MODULE__{}]
  def search_published_insights(search_term, opts) do
    public_insights_query(opts)
    |> Sanbase.Insight.Search.run(search_term, opts)
    |> Enum.map(& &1.post)
  end

  def related_projects(%Post{} = post) do
    tags =
      post
      |> Repo.preload([:tags])
      |> Map.get(:tags, [])
      |> Enum.map(& &1.name)

    projects = Project.List.by_field(tags, :ticker)

    {:ok, projects}
  end

  def base_insights_query(opts) do
    base_query()
    |> by_is_pulse(Keyword.get(opts, :is_pulse, nil))
    |> by_is_paywall_required(Keyword.get(opts, :is_paywall_required, nil))
    |> maybe_filter_by_tags(Keyword.get(opts, :tags, nil))
    |> by_from_to_datetime(opts)
    |> maybe_distinct(opts)
    |> maybe_order_by_published_at(opts)
    |> page(opts)
    |> maybe_preload(opts)
  end

  defp base_query(_opts \\ []) do
    from(p in __MODULE__, where: p.is_deleted != true)
  end

  @doc """
  All insights for given user_id, including drafts. This is used when the current
  user fetches their own insights list.
  """
  def user_insights(user_id, opts \\ []) do
    base_insights_query(opts)
    |> by_user(user_id)
    |> Repo.all()
  end

  @doc """
  All published insights for given user_id. This is used when the current user
  is fetching data for another user.
  """
  def user_public_insights(user_id, opts \\ []) do
    base_insights_query(opts)
    |> by_user(user_id)
    |> filter_published_and_approved()
    |> Repo.all()
  end

  @doc """
  Fetch public (published and approved) insights.
  """
  def public_insights(opts \\ []) do
    public_insights_query(opts)
    |> Repo.all()
  end

  @doc """
  All public insights published after datetime
  """
  def public_insights_after(datetime, opts \\ []) do
    public_insights_query(opts)
    |> after_datetime(datetime)
    |> Repo.all()
  end

  def public_insights_by_tags(tags, opts \\ []) when is_list(tags) do
    public_insights_query(opts)
    |> by_tags(tags)
    |> Repo.all()
  end

  @doc """
  All published and approved insights that given user has voted for
  """
  def all_insights_user_voted_for(user_id, opts \\ []) do
    public_insights_query(opts)
    |> user_has_voted_for(user_id)
    |> Repo.all()
  end

  @doc """
  Change insights owner to be the fallback user
  """
  def assign_all_user_insights_to_anonymous(user_id) do
    anon_user_id = User.anonymous_user_id()

    # This should also be applied to posts with is_deleted == true
    from(p in Post, where: p.user_id == ^user_id)
    |> Repo.update_all(set: [user_id: anon_user_id])
  end

  def create_chart_event(
        user_id,
        %{chart_configuration_id: chart_configuration_id} = args
      ) do
    case Configuration.by_id(chart_configuration_id, querying_user_id: user_id) do
      {:ok, conf} ->
        args =
          Map.merge(args, %{
            chart_configuration_for_event_id: conf.id,
            is_chart_event: true
          })

        case create(%User{id: user_id}, args) do
          {:ok, post} ->
            publish(post.id, user_id)

          {:error, error} ->
            {:error, error}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  def user_id_to_post_ids_list() do
    from(
      p in base_query(),
      select: {p.user_id, fragment("array_agg(?)", p.id)},
      group_by: p.user_id
    )
    |> Repo.all()
  end

  def pulse?(%__MODULE__{is_pulse: is_pulse}), do: is_pulse

  def featured_posts_query() do
    from(
      p in Post,
      left_join: featured_item in Sanbase.FeaturedItem,
      on: p.id == featured_item.post_id,
      where: not is_nil(featured_item.id),
      preload: [:user]
    )
    |> distinct(true)
  end

  # Helper functions

  defp public_insights_query(opts) do
    base_insights_query(opts)
    |> filter_published_and_approved()
  end

  defp publish_post(post) do
    # Automatically approve insights of santiment users.
    # Otherwise set to awaiting_approval and require a moderator to approve it
    # before other people see it
    state =
      case post do
        %{user: %{email: email}} when is_binary(email) ->
          if String.ends_with?(email, "@santiment.net"), do: @approved, else: @awaiting_approval

        _ ->
          @awaiting_approval
      end

    publish_changeset =
      publish_changeset(post, %{ready_state: Post.published(), state: state})

    publish_changeset
    |> Repo.update()
    |> case do
      {:ok, post} ->
        # Send notification to discird
        Task.Supervisor.async_nolink(Sanbase.TaskSupervisor, fn ->
          post = Sanbase.Repo.preload(post, :user)
          Sanbase.Messaging.Insight.publish_in_discord(post)
        end)

        # Update the embeddings
        async_embed_post(post)

        # Auto-categorize the insight (only if no human categories exist)
        async_categorize_post(post)

        # Create a timeline event
        TimelineEvent.maybe_create_event_async(
          TimelineEvent.publish_insight_type(),
          post,
          publish_changeset
        )

        {:ok, post}

      error ->
        error
    end
  end

  defp unpublish_post(post) do
    publish_changeset(post, %{ready_state: Post.draft()})
    |> Repo.update()
  end

  defp by_user(query, user_id) do
    from(
      p in query,
      where: p.user_id == ^user_id
    )
  end

  defp by_is_pulse(query, nil), do: query

  defp by_is_pulse(query, is_pulse) do
    from(
      p in query,
      where: p.is_pulse == ^is_pulse
    )
  end

  defp by_is_paywall_required(query, nil), do: query

  defp by_is_paywall_required(query, is_paywall_required) do
    from(
      p in query,
      where: p.is_paywall_required == ^is_paywall_required
    )
  end

  defp by_from_to_datetime(query, opts) do
    case {Keyword.get(opts, :from), Keyword.get(opts, :to)} do
      {from, to} when not is_nil(from) and not is_nil(to) ->
        from(
          p in query,
          where: p.published_at >= ^from and p.published_at <= ^to
        )

      _ ->
        query
    end
  end

  defp maybe_filter_by_tags(query, nil), do: query

  defp maybe_filter_by_tags(query, tags) when is_list(tags) do
    query
    |> join(:left, [p], t in assoc(p, :tags))
    |> where([_p, t], t.name in ^tags)
  end

  defp by_tags(query, tags) do
    query
    |> join(:left, [p], t in assoc(p, :tags))
    |> where([_p, t], t.name in ^tags)
  end

  defp filter_published_and_approved(query) do
    query
    |> where([p], p.ready_state == ^@published and p.state == ^@approved)
  end

  defp user_has_voted_for(query, user_id) do
    query
    |> join(:left, [p], v in assoc(p, :votes))
    |> where([_p, v], v.user_id == ^user_id)
  end

  defp maybe_order_by_published_at(query, opts) do
    case Keyword.get(opts, :ordered?, true) do
      true ->
        from(
          p in query,
          order_by: [desc: p.published_at]
        )

      false ->
        query
    end
  end

  defp after_datetime(query, datetime) do
    from(
      p in query,
      where: p.published_at >= ^datetime,
      preload: [:tags, :user],
      select: [:id, :title, :published_at, :user_id]
    )
  end

  defp page(query, opts) do
    if Keyword.get(opts, :page) && Keyword.get(opts, :page_size) do
      {limit, offset} = Sanbase.Utils.Transform.opts_to_limit_offset(opts)

      query
      |> limit(^limit)
      |> offset(^offset)
    else
      query
    end
  end

  # If only the tags or images change, then the `updated_at` is not changed.
  # The post should be considered as changed in this case as well. This will
  # also trigger the after update changes as well
  defp maybe_add_updated_at(%Ecto.Changeset{} = changeset) do
    case map_size(changeset.changes) do
      0 ->
        changeset

      _ ->
        changeset
        |> change(%{
          updated_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
        })
    end
  end

  defp maybe_preload(query, opts) do
    case Keyword.get(opts, :preload?, true) do
      true ->
        preloads = Keyword.get(opts, :preload, @preloads)
        query |> preload(^preloads)

      false ->
        query
    end
  end

  defp maybe_distinct(query, opts) do
    case Keyword.get(opts, :distinct?, true) do
      true -> from(p in query, distinct: true)
      false -> query
    end
  end

  defp images_cast(changeset, %{image_urls: image_urls}) do
    images = PostImage |> where([i], i.image_url in ^image_urls) |> Repo.all()

    if Enum.any?(images, fn %{post_id: post_id} -> not is_nil(post_id) end) do
      changeset
      |> Ecto.Changeset.add_error(
        :images,
        "The images you are trying to use are already used in another insight"
      )
    else
      changeset
      |> put_assoc(:images, images)
    end
  end

  defp images_cast(changeset, _), do: changeset

  defp extract_image_url_from_post(%Post{} = post) do
    post
    |> Repo.preload(:images)
    |> Map.get(:images, [])
    |> Enum.map(fn %{image_url: image_url} -> image_url end)
  end

  def delete_post_images(%Post{} = post) do
    extract_image_url_from_post(post)
    |> Enum.map(&Sanbase.FileStore.delete/1)
  end

  defp maybe_drop_post_tags(post, %{tags: tags}) when is_list(tags),
    do: Tag.drop_tags(post)

  defp maybe_drop_post_tags(_, _), do: :ok

  defp valid_prediction?(_, nil), do: []
  defp valid_prediction?(_, prediction) when prediction in @predictions, do: []

  defp valid_prediction?(_, prediction) do
    [
      prediction: """
      The prediction #{inspect(prediction)} is not supported.
      Supported predictions are: #{@predictions |> Enum.join(", ")}
      """
    ]
  end

  defp maybe_apply_projects_filter_query(query, opts) do
    case Keyword.get(opts, :filter) do
      %{project_ids: project_ids} ->
        query |> where([p], p.price_chart_project_id in ^project_ids)

      _ ->
        query
    end
  end

  defp async_embed_post(%__MODULE__{} = post) do
    if Application.get_env(:sanbase, :env) != :test do
      Task.Supervisor.async_nolink(Sanbase.TaskSupervisor, fn ->
        Sanbase.Insight.PostEmbedding.embed_post(post)
      end)
    end
  end

  defp async_categorize_post(%__MODULE__{} = post) do
    if Application.get_env(:sanbase, :env) != :test do
      Task.Supervisor.async_nolink(Sanbase.TaskSupervisor, fn ->
        # Only categorize if no human-sourced categories exist
        unless Sanbase.Insight.PostCategory.has_human_categories?(post.id) do
          case Sanbase.Insight.Categorizer.categorize_insight(post.id, save: true, force: false) do
            {:ok, _categories} ->
              Logger.debug("Auto-categorized insight #{post.id}")

            {:error, reason} ->
              Logger.warning("Failed to auto-categorize insight #{post.id}: #{inspect(reason)}")
          end
        end
      end)
    end
  end
end
