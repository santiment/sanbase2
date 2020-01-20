defmodule Sanbase.Insight.Post do
  use Ecto.Schema

  use Timex.Ecto.Timestamps

  import Ecto.Changeset
  import Ecto.Query
  import Sanbase.Utils.ErrorHandling, only: [changeset_errors_to_str: 1]

  alias Sanbase.Tag
  alias Sanbase.Repo
  alias Sanbase.Auth.User
  alias Sanbase.Model.Project
  alias Sanbase.Vote
  alias Sanbase.Insight.{Post, PostImage}
  alias Sanbase.Timeline.TimelineEvent

  require Logger

  @preloads [:votes, :user, :images, :tags]
  # state
  @awaiting_approval "awaiting_approval"
  @approved "approved"
  @declined "declined"

  # ready_state
  @draft "draft"
  @published "published"

  schema "posts" do
    belongs_to(:user, User)
    has_many(:votes, Vote, on_delete: :delete_all)

    field(:title, :string)
    field(:short_desc, :string)
    field(:link, :string)
    field(:text, :string)
    field(:state, :string, default: @approved)
    field(:moderation_comment, :string)
    field(:ready_state, :string, default: @draft)

    has_many(:images, PostImage, on_delete: :delete_all)
    has_one(:featured_item, Sanbase.FeaturedItem, on_delete: :delete_all)
    has_many(:timeline_events, TimelineEvent, on_delete: :delete_all)

    many_to_many(
      :tags,
      Tag,
      join_through: "posts_tags",
      on_replace: :delete,
      on_delete: :delete_all
    )

    field(:published_at, :naive_datetime)
    timestamps()
  end

  # Needed by ex_admin :(
  def changeset(%Post{} = post, attrs \\ %{}) do
    post |> cast(attrs, [])
  end

  def create_changeset(%Post{} = post, attrs) do
    post
    |> cast(attrs, [:title, :short_desc, :link, :text, :user_id])
    |> Tag.put_tags(attrs)
    |> images_cast(attrs)
    |> validate_required([:user_id, :title])
    |> validate_length(:title, max: 140)
  end

  def update_changeset(%Post{} = post, attrs) do
    post
    |> cast(attrs, [:title, :short_desc, :link, :text, :moderation_comment, :state])
    |> Tag.put_tags(attrs)
    |> images_cast(attrs)
    |> validate_length(:title, max: 140)
  end

  def publish_changeset(%Post{} = post, attrs) do
    post
    |> cast(attrs, [:ready_state, :published_at])
    |> change(published_at: NaiveDateTime.utc_now())
  end

  def awaiting_approval_state(), do: @awaiting_approval
  def approved_state(), do: @approved
  def declined_state(), do: @declined

  def published(), do: @published
  def draft(), do: @draft

  def by_id(post_id) do
    from(p in __MODULE__, preload: ^@preloads)
    |> Repo.get(post_id)
    |> case do
      nil -> {:error, "There is no insight with id #{post_id}"}
      post -> {:ok, post |> Tag.Preloader.order_tags()}
    end
  end

  def create(%User{id: user_id}, args) do
    %__MODULE__{user_id: user_id}
    |> create_changeset(args)
    |> Repo.insert()
    |> case do
      {:ok, post} ->
        {:ok, post |> Tag.Preloader.order_tags()}

      {:error, changeset} ->
        {
          :error,
          message: "Cannot create insight", details: changeset_errors_to_str(changeset)
        }
    end
  end

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
            {:ok, post |> Tag.Preloader.order_tags()}

          {:error, error} ->
            {:error, error}
        end

      %__MODULE__{user_id: another_user_id} when user_id != another_user_id ->
        {:error, "Cannot update not owned insight: #{post_id}"}

      {:error, changeset} ->
        {
          :error,
          message: "Cannot update insight", details: changeset_errors_to_str(changeset)
        }

      _post ->
        {:error, "Cannot update insight with id: #{post_id}"}
    end
  end

  def delete(post_id, %User{id: user_id}) do
    case Repo.get(Post, post_id) do
      %__MODULE__{user_id: ^user_id} = post ->
        # Delete the images from the S3/Local store.
        delete_post_images(post)

        # Note: When ecto changeset middleware is implemented return just `Repo.delete(post)`
        case Repo.delete(post) do
          {:ok, post} ->
            {:ok, post |> Tag.Preloader.order_tags()}

          {:error, changeset} ->
            {
              :error,
              message: "Cannot delete post with id #{post_id}",
              details: changeset_errors_to_str(changeset)
            }
        end

      _post ->
        {:error, "You don't own the post with id #{post_id}"}
    end
  end

  def publish(post_id, user_id) do
    post_id = String.to_integer(post_id)
    post = Repo.get(Post, post_id)

    with {:nil?, %Post{id: ^post_id}} <- {:nil?, post},
         {:own_post?, %Post{user_id: ^user_id}} <- {:own_post?, post},
         {:draft?, %Post{ready_state: @draft}} <- {:draft?, post},
         {:ok, post} <- publish_post(post) do
      {:ok, post |> Tag.Preloader.order_tags()}
    else
      {:nil?, nil} ->
        {:error, "Cannot publish insight with id #{post_id}"}

      {:draft?, _} ->
        {:error, "Cannot publish already published insight with id: #{post_id}"}

      {:own_post?, _} ->
        {:error, "Cannot publish not own insight with id: #{post_id}"}

      {:error, error} ->
        error_message = "Cannot publish insight with id #{post_id}"
        Logger.error("#{error_message}, #{inspect(error)}")
        {:error, error_message}
    end
  end

  def preloads(), do: @preloads

  def related_projects(%Post{} = post) do
    tags =
      post
      |> Repo.preload([:tags])
      |> Map.get(:tags)
      |> Enum.map(& &1.name)

    projects = Project.List.by_field(tags, :ticker)

    {:ok, projects}
  end

  @doc """
  All insights for given user_id
  """
  def user_insights(user_id) do
    Post
    |> by_user(user_id)
    |> Repo.all()
    |> Repo.preload(@preloads)
    |> Tag.Preloader.order_tags()
  end

  @doc """
  All published insights for given user_id
  """
  def user_public_insights(user_id) do
    published_and_approved_insights()
    |> by_user(user_id)
    |> Repo.all()
    |> Repo.preload(@preloads)
    |> Tag.Preloader.order_tags()
  end

  @doc """
  All public (published and approved) insights paginated
  """
  def public_insights(page, page_size) do
    published_and_approved_insights()
    |> order_by_published_at()
    |> page(page, page_size)
    |> Repo.all()
    |> Repo.preload(@preloads)
    |> Tag.Preloader.order_tags()
  end

  @doc """
  All public insights published after datetime
  """
  def public_insights_after(datetime) do
    published_and_approved_insights()
    |> after_datetime(datetime)
    |> order_by_published_at()
    |> Repo.all()
    |> Tag.Preloader.order_tags()
  end

  @doc """
  All published and approved insights by given tag
  """
  def public_insights_by_tag(tag) do
    published_and_approved_insights()
    |> by_tag(tag)
    |> order_by_published_at()
    |> Repo.all()
    |> Repo.preload(@preloads)
  end

  def public_insights_by_tags(tags, page, page_size) when is_list(tags) do
    published_and_approved_insights()
    |> by_tags(tags)
    |> distinct(true)
    |> order_by_published_at()
    |> page(page, page_size)
    |> Repo.all()
    |> Repo.preload(@preloads)
  end

  @doc """
  All published and approved insights that given user has voted for
  """
  def all_insights_user_voted_for(user_id) do
    published_and_approved_insights()
    |> user_has_voted_for(user_id)
    |> Repo.all()
    |> Repo.preload(@preloads)
  end

  @doc """
  Change insights owner to be the fallback user
  """
  def assign_all_user_insights_to_anonymous(user_id) do
    anon_user_id = User.anonymous_user_id()

    from(p in Post, where: p.user_id == ^user_id)
    |> Repo.update_all(set: [user_id: anon_user_id])
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

  defp by_tag(query, tag_name) do
    query
    |> join(:left, [p], t in assoc(p, :tags))
    |> where([_p, t], t.name == ^tag_name)
  end

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

  defp page(query, page, page_size) do
    query
    |> offset(^((page - 1) * page_size))
    |> limit(^page_size)
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

  defp delete_post_images(%Post{} = post) do
    extract_image_url_from_post(post)
    |> Enum.map(&Sanbase.FileStore.delete/1)
  end

  defp maybe_drop_post_tags(post, %{tags: tags}) when is_list(tags) do
    Tag.drop_tags(post)
  end

  defp maybe_drop_post_tags(_, _), do: :ok
end
