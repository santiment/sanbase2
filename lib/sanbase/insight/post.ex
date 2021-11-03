defmodule Sanbase.Insight.Post do
  use Ecto.Schema

  import Ecto.Query
  import Ecto.Changeset
  import Sanbase.Insight.EventEmitter, only: [emit_event: 3]
  import Sanbase.Utils.ErrorHandling, only: [changeset_errors: 1]

  alias Sanbase.Tag
  alias Sanbase.Repo
  alias Sanbase.Accounts.User
  alias Sanbase.Model.Project
  alias Sanbase.Insight.{Post, PostImage}
  alias Sanbase.Timeline.TimelineEvent
  alias Sanbase.Metric.MetricPostgresData
  alias Sanbase.Chart.Configuration

  require Logger
  require Sanbase.Utils.Config, as: Config

  @preloads [:user, :images, :tags, :chart_configuration_for_event]
  # state
  @awaiting_approval "awaiting_approval"
  @approved "approved"
  @declined "declined"

  # ready_state
  @draft "draft"
  @published "published"

  @type opts :: [
          is_pulse: boolean(),
          is_paywall_required: boolean(),
          from: DateTime.t(),
          to: DateTime.t(),
          page: non_neg_integer(),
          page_size: non_neg_integer()
        ]

  schema "posts" do
    belongs_to(:user, User)

    field(:title, :string)
    field(:short_desc, :string)
    field(:text, :string)
    field(:state, :string, default: @approved)
    field(:moderation_comment, :string)
    field(:ready_state, :string, default: @draft)
    field(:is_pulse, :boolean, default: false)
    field(:is_paywall_required, :boolean, default: false)
    field(:prediction, :string, default: "unspecified")

    # Chart events are insights connected to specific chart configuration and datetime
    field(:is_chart_event, :boolean, default: false)
    field(:chart_event_datetime, :utc_datetime)
    belongs_to(:chart_configuration_for_event, Configuration)

    belongs_to(:price_chart_project, Project)

    has_one(:featured_item, Sanbase.FeaturedItem, on_delete: :delete_all)

    has_many(:chart_configurations, Configuration)
    has_many(:images, PostImage, on_delete: :delete_all)
    has_many(:timeline_events, TimelineEvent, on_delete: :delete_all)
    has_many(:votes, Sanbase.Vote, on_delete: :delete_all)

    # has_many(:post_comments, Sanbase.Comment.PostComment, on_delete: :delete_all)

    # has_many(:comments,
    #   through: [:post_comments, :comments],
    #   on_delete: :delete_all
    # )

    # many_to_many(:comments, Sanbase.Comment,
    #   join_through: "post_comments_mapping",
    #   on_delete: :delete_all
    # )

    many_to_many(:tags, Tag,
      join_through: "posts_tags",
      on_replace: :delete,
      on_delete: :delete_all
    )

    many_to_many(:metrics, MetricPostgresData,
      join_through: "posts_metrics",
      join_keys: [post_id: :id, metric_id: :id],
      on_replace: :delete,
      on_delete: :delete_all
    )

    field(:published_at, :naive_datetime)
    timestamps()
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
         %{total_count: total, draft_count: draft, pulse_count: pulse, paywall_count: paywall}}
      end)

    {:ok, map}
  end

  def can_create?(user_id) do
    limits = %{
      day: Config.get(:creation_limit_day, 20),
      hour: Config.get(:creation_limit_hour, 10),
      minute: Config.get(:creation_limit_minute, 3)
    }

    Sanbase.Ecto.Common.can_create?(__MODULE__, user_id,
      limits: limits,
      entity_singular: "insight",
      entity_plural: "insights"
    )
  end

  # Needed by ex_admin
  def changeset(%Post{} = post, attrs \\ %{}) do
    post |> cast(attrs, [])
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

  def update_changeset(%Post{} = post, attrs) do
    attrs = Sanbase.DateTimeUtils.truncate_datetimes(attrs)

    preloads =
      if(attrs[:tags], do: [:tags], else: []) ++ if attrs[:metrics], do: [:metrics], else: []

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
    |> cast(attrs, [:ready_state, :published_at])
    |> change(published_at: naive_now)
  end

  def awaiting_approval_state(), do: @awaiting_approval
  def approved_state(), do: @approved
  def declined_state(), do: @declined
  def published(), do: @published
  def draft(), do: @draft
  def preloads(), do: @preloads

  def is_published?(%Post{ready_state: ready_state}), do: ready_state == @published

  def by_id(post_id) do
    from(p in __MODULE__, preload: ^@preloads)
    |> Repo.get(post_id)
    |> case do
      nil -> {:error, "There is no insight with id #{post_id}"}
      post -> {:ok, post |> Tag.Preloader.order_tags()}
    end
  end

  @spec create(%User{}, map()) :: {:ok, %__MODULE__{}} | {:error, Keyword.t()}
  def create(%User{id: user_id}, args) do
    %__MODULE__{user_id: user_id}
    |> create_changeset(args)
    |> Repo.insert()
    |> case do
      {:ok, post} ->
        emit_event({:ok, post}, :create_insight, %{})
        :ok = Sanbase.Insight.Search.update_document_tokens(post.id)
        {:ok, post |> Tag.Preloader.order_tags()}

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
    case Repo.get(__MODULE__, post_id) do
      %__MODULE__{user_id: ^user_id} = post ->
        # If the tags are updated they need to be dropped from the mapping table
        # and inserted again as the order needs to be preserved.
        maybe_drop_post_tags(post, args)

        post
        |> Repo.preload([:tags, :images])
        |> update_changeset(args)
        |> Repo.update()
        |> case do
          {:ok, post} ->
            emit_event({:ok, post}, :update_insight, %{})
            :ok = Sanbase.Insight.Search.update_document_tokens(post.id)
            {:ok, post |> Tag.Preloader.order_tags()}

          {:error, error} ->
            {:error, error}
        end

      %__MODULE__{user_id: another_user_id} when user_id != another_user_id ->
        {:error, "Cannot update not owned insight: #{post_id}"}

      {:error, changeset} ->
        {:error, message: "Cannot update insight", details: changeset_errors(changeset)}

      _post ->
        {:error, "Cannot update insight with id: #{post_id}"}
    end
  end

  @spec delete(non_neg_integer(), %User{}) ::
          {:ok, %__MODULE__{}} | {:error, String.t()} | {:error, Keyword.t()}
  def delete(post_id, %User{id: user_id}) do
    case Repo.get(Post, post_id) do
      %__MODULE__{user_id: ^user_id} = post ->
        # Delete the images from the S3/Local store.
        delete_post_images(post)

        # Note: When ecto changeset middleware is implemented return just `Repo.delete(post)`
        case Repo.delete(post) do
          {:ok, post} ->
            emit_event({:ok, post}, :delete_insight, %{})

            {:ok, post |> Tag.Preloader.order_tags()}

          {:error, changeset} ->
            {:error,
             message: "Cannot delete post with id #{post_id}",
             details: changeset_errors(changeset)}
        end

      _post ->
        {:error, "You don't own the post with id #{post_id}"}
    end
  end

  def publish(post_id, user_id) do
    post_id = Sanbase.Math.to_integer(post_id)
    post = Repo.get(Post, post_id)

    with {_, %Post{id: ^post_id}} <- {:nil?, post},
         {_, %Post{user_id: ^user_id}} <- {:own_post?, post},
         {_, %Post{ready_state: @draft}} <- {:draft?, post},
         {:ok, post} <- publish_post(post) do
      emit_event({:ok, post}, :publish_insight, %{})

      {:ok, post |> Repo.preload(@preloads) |> Tag.Preloader.order_tags()}
    else
      {:nil?, nil} ->
        {:error, "Cannot publish insight with id #{post_id}"}

      {:draft?, _} ->
        {:error, "Cannot publish already published insight with id: #{post_id}"}

      {:own_post?, _} ->
        {:error, "Cannot publish not own insight with id: #{post_id}"}

      {:error, error} ->
        error_message = "Cannot publish insight with id #{post_id}"
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

  @spec search_published_insights_highglight(String.t(), opts) :: [%{}]
  def search_published_insights_highglight(search_term, opts) do
    public_insights_query(opts) |> Sanbase.Insight.Search.run(search_term, opts)
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

  @doc """
  All insights for given user_id
  """
  def user_insights(user_id, opts \\ []) do
    Post
    |> by_user(user_id)
    |> by_is_pulse(Keyword.get(opts, :is_pulse, nil))
    |> by_is_paywall_required(Keyword.get(opts, :is_paywall_required, nil))
    |> order_by_published_at()
    |> page(opts)
    |> preload(^@preloads)
    |> Repo.all()
    |> Tag.Preloader.order_tags()
  end

  @doc """
  All published insights for given user_id
  """
  def user_public_insights(user_id, opts \\ []) do
    published_and_approved_insights()
    |> by_user(user_id)
    |> by_is_pulse(Keyword.get(opts, :is_pulse, nil))
    |> by_is_paywall_required(Keyword.get(opts, :is_paywall_required, nil))
    |> by_from_to_datetime(Keyword.get(opts, :from, nil), Keyword.get(opts, :to, nil))
    |> order_by_published_at()
    |> page(opts)
    |> preload(^@preloads)
    |> Repo.all()
    |> Tag.Preloader.order_tags()
  end

  @doc """
  All public (published and approved) insights paginated
  """
  def public_insights(page, page_size, opts \\ []) do
    public_insights_query(opts)
    |> order_by_published_at()
    |> page(page, page_size)
    |> Repo.all()
    |> Tag.Preloader.order_tags()
  end

  def public_insights_query(opts \\ []) do
    published_and_approved_insights()
    |> by_is_pulse(Keyword.get(opts, :is_pulse, nil))
    |> by_is_paywall_required(Keyword.get(opts, :is_paywall_required, nil))
    |> by_from_to_datetime(Keyword.get(opts, :from, nil), Keyword.get(opts, :to, nil))
    |> preload(^@preloads)
  end

  @doc """
  All public insights published after datetime
  """
  def public_insights_after(datetime, opts \\ []) do
    published_and_approved_insights()
    |> by_is_pulse(Keyword.get(opts, :is_pulse, nil))
    |> by_is_paywall_required(Keyword.get(opts, :is_paywall_required, nil))
    |> after_datetime(datetime)
    |> order_by_published_at()
    |> Repo.all()
    |> Tag.Preloader.order_tags()
  end

  def public_insights_by_tags(tags, opts \\ []) when is_list(tags) do
    published_and_approved_insights()
    |> by_tags(tags)
    |> by_is_pulse(Keyword.get(opts, :is_pulse, nil))
    |> by_is_paywall_required(Keyword.get(opts, :is_paywall_required, nil))
    |> by_from_to_datetime(Keyword.get(opts, :from, nil), Keyword.get(opts, :to, nil))
    |> distinct(true)
    |> order_by_published_at()
    |> preload(^@preloads)
    |> Repo.all()
    |> Tag.Preloader.order_tags()
  end

  def public_insights_by_tags(tags, page, page_size, opts \\ []) when is_list(tags) do
    published_and_approved_insights()
    |> by_tags(tags)
    |> by_is_pulse(Keyword.get(opts, :is_pulse, nil))
    |> by_is_paywall_required(Keyword.get(opts, :is_paywall_required, nil))
    |> by_from_to_datetime(Keyword.get(opts, :from, nil), Keyword.get(opts, :to, nil))
    |> distinct(true)
    |> order_by_published_at()
    |> page(page, page_size)
    |> preload(^@preloads)
    |> Repo.all()
    |> Tag.Preloader.order_tags()
  end

  @doc """
  All published and approved insights that given user has voted for
  """
  def all_insights_user_voted_for(user_id, opts \\ []) do
    published_and_approved_insights()
    |> user_has_voted_for(user_id)
    |> by_is_pulse(Keyword.get(opts, :is_pulse, nil))
    |> by_is_paywall_required(Keyword.get(opts, :is_paywall_required, nil))
    |> by_from_to_datetime(Keyword.get(opts, :from, nil), Keyword.get(opts, :to, nil))
    |> preload(^@preloads)
    |> Repo.all()
    |> Tag.Preloader.order_tags()
  end

  @doc """
  Change insights owner to be the fallback user
  """
  def assign_all_user_insights_to_anonymous(user_id) do
    anon_user_id = User.anonymous_user_id()

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
      p in Post,
      select: {p.user_id, fragment("array_agg(?)", p.id)},
      group_by: p.user_id
    )
    |> Repo.all()
  end

  # Helper functions

  defp publish_post(post) do
    publish_changeset = publish_changeset(post, %{ready_state: Post.published()})

    publish_changeset
    |> Repo.update()
    |> case do
      {:ok, post} ->
        Task.Supervisor.async_nolink(Sanbase.TaskSupervisor, fn ->
          post = Sanbase.Repo.preload(post, :user)
          Sanbase.Notifications.Insight.publish_in_discord(post)
        end)

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

  defp by_from_to_datetime(query, from, to) when not is_nil(from) and not is_nil(to) do
    from(
      p in query,
      where: p.published_at >= ^from and p.published_at <= ^to
    )
  end

  defp by_from_to_datetime(query, _, _), do: query

  defp by_tags(query, tags) do
    query
    |> join(:left, [p], t in assoc(p, :tags))
    |> where([_p, t], t.name in ^tags)
  end

  defp published_and_approved_insights() do
    from(
      p in Post,
      where:
        p.ready_state == ^@published and
          p.state == ^@approved
    )
  end

  defp user_has_voted_for(query, user_id) do
    query
    |> join(:left, [p], v in assoc(p, :votes))
    |> where([_p, v], v.user_id == ^user_id)
  end

  defp order_by_published_at(query) do
    from(
      p in query,
      order_by: [desc: p.published_at]
    )
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
    page = Keyword.get(opts, :page, nil)
    page_size = Keyword.get(opts, :page_size, nil)

    if page && page_size do
      page(query, page, page_size)
    else
      query
    end
  end

  defp page(query, page, page_size) do
    query
    |> offset(^((page - 1) * page_size))
    |> limit(^page_size)
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
        |> change(%{updated_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)})
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

  defp maybe_drop_post_tags(post, %{tags: tags}) when is_list(tags), do: Tag.drop_tags(post)
  defp maybe_drop_post_tags(_, _), do: :ok

  @predictions [
    "heavy_bullish",
    "semi_bullish",
    "semi_bearish",
    "heavy_bearish",
    "unspecified",
    "none"
  ]
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
end
