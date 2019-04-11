defmodule Sanbase.Insight.Post do
  use Ecto.Schema

  use Timex.Ecto.Timestamps

  import Ecto.Changeset
  import Ecto.Query

  alias Sanbase.Tag
  alias Sanbase.Insight.{Poll, Post, Vote, PostImage}
  alias Sanbase.Auth.User
  alias Sanbase.Timeline.TimelineEvent

  alias Sanbase.Repo
  alias Ecto.Multi

  require Logger

  # state
  @awaiting_approval "awaiting_approval"
  @approved "approved"
  @declined "declined"

  # ready_state
  @draft "draft"
  @published "published"

  schema "posts" do
    belongs_to(:poll, Poll)
    belongs_to(:user, User)
    has_many(:votes, Vote, on_delete: :delete_all)

    field(:title, :string)
    field(:short_desc, :string)
    field(:link, :string)
    field(:text, :string)
    field(:state, :string, default: @awaiting_approval)
    field(:moderation_comment, :string)
    field(:ready_state, :string, default: @draft)
    field(:discourse_topic_url, :string)

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

    timestamps()
  end

  # Needed by ex_admin :(
  def changeset(%Post{} = post, attrs \\ %{}) do
    post |> cast(attrs, [])
  end

  def create_changeset(%Post{} = post, attrs) do
    post
    |> cast(attrs, [:title, :short_desc, :link, :text, :user_id, :poll_id])
    |> Tag.put_tags(attrs)
    |> images_cast(attrs)
    |> validate_required([:poll_id, :user_id, :title])
    |> validate_length(:title, max: 140)
    |> unique_constraint(:poll_id, name: :posts_poll_id_title_index)
  end

  def update_changeset(%Post{} = post, attrs) do
    post
    |> cast(attrs, [:title, :short_desc, :link, :text, :moderation_comment, :state])
    |> Tag.put_tags(attrs)
    |> images_cast(attrs)
    |> validate_required([:poll_id, :user_id, :title])
    |> validate_length(:title, max: 140)
    |> unique_constraint(:poll_id, name: :posts_poll_id_title_index)
  end

  def publish_changeset(%Post{} = post, attrs) do
    post
    |> cast(attrs, [:ready_state, :discourse_topic_url])
  end

  def awaiting_approval_state(), do: @awaiting_approval
  def approved_state(), do: @approved
  def declined_state(), do: @declined

  def published(), do: @published
  def draft(), do: @draft

  def publish(post_id, user_id) do
    post_id = String.to_integer(post_id)
    post = Repo.get(Post, post_id)
    draft = draft()

    with {:nil?, %Post{id: ^post_id}} <- {:nil?, post},
         {:own_post?, %Post{user_id: ^user_id}} <- {:own_post?, post},
         {:draft?, %Post{ready_state: ^draft}} <- {:draft?, post},
         {:ok, %{post: post}} <- publish_post(post, user_id) do
      {:ok, post}
    else
      {:nil?, nil} ->
        {:error, "Can't publish post with id #{post_id}"}

      {:draft?, _} ->
        {:error, "Can't publish already published post with id: #{post_id}"}

      {:own_post?, _} ->
        {:error, "Can't publish not own post with id: #{post_id}"}

      {:error, _, error, _} ->
        error_message = "Can't publish post with id #{post_id}"
        Logger.error("#{error_message}, #{inspect(error)}")
        {:error, error_message}
    end
  end

  @doc """
    Returns all posts ranked by HN ranking algorithm: https://news.ycombinator.com/item?id=1781013
    where gravity = 1.8
    formula: votes / pow((item_hour_age + 2), gravity)
  """
  @spec posts_by_score() :: [%Post{}]
  def posts_by_score() do
    gravity = 1.8

    query = """
      SELECT * FROM
        (SELECT
          posts_by_votes.*,
          ((posts_by_votes.votes_count) / POWER(posts_by_votes.item_hour_age + 2, #{gravity})) as score
          FROM
            (SELECT
              p.*,
              (EXTRACT(EPOCH FROM current_timestamp - p.inserted_at) /3600)::Integer as item_hour_age,
              count(*) AS votes_count
              FROM posts AS p
              LEFT JOIN votes AS v ON p.id = v.post_id
              GROUP BY p.id
              ORDER BY votes_count DESC
            ) AS posts_by_votes
          ORDER BY score DESC
        ) AS ranked_posts;
    """

    result = Ecto.Adapters.SQL.query!(Repo, query)

    result.rows
    |> Enum.map(fn row ->
      Repo.load(Post, {result.columns, row})
    end)
  end

  @doc """
    Returns only published posts ranked by the ranking algorithm
  """
  @spec ranked_published_posts() :: [%Post{}]
  def ranked_published_posts() do
    posts_by_score()
    |> Enum.filter(&(&1.ready_state == published()))
  end

  @doc """
    Returns published or current user's posts ranked by the ranking algorithm
  """
  @spec ranked_published_or_own_posts(integer) :: [%Post{}]
  def ranked_published_or_own_posts(user_id) do
    posts_by_score()
    |> get_only_published_or_own_posts(user_id)
  end

  @doc """
  All insights for given user_id
  """
  def user_insights(user_id) do
    from(
      p in Post,
      where: p.user_id == ^user_id
    )
    |> Repo.all()
  end

  @doc """
  All published insights for given user_id
  """
  def user_published_insights(user_id) do
    from(
      p in Post,
      where: p.user_id == ^user_id and p.ready_state == ^@published
    )
    |> Repo.all()
  end

  def published_posts(page, page_size) do
    from(
      p in Post,
      where: p.ready_state == ^@published and p.state == ^@approved,
      order_by: [desc: p.updated_at],
      limit: ^page_size,
      offset: ^((page - 1) * page_size)
    )
    |> Repo.all()
  end

  @doc """
    Change insights owner to be the fallback user
  """
  def change_owner_to_anonymous(user_id) do
    anon_user_id =
      User
      |> Repo.get_by(username: User.insights_fallback_username())
      |> Map.get(:id)

    from(p in Post, where: p.user_id == ^user_id)
    |> Repo.update_all(set: [user_id: anon_user_id])
  end

  # Helper functions

  defp publish_post(post, user_id) do
    Multi.new()
    |> Multi.run(:discourse_topic_url, fn _ ->
      Sanbase.Discourse.Insight.create_discourse_topic(post)
    end)
    |> Multi.run(:post, fn %{discourse_topic_url: discourse_topic_url} ->
      publish_changeset(post, %{
        discourse_topic_url: discourse_topic_url,
        ready_state: Post.published()
      })
      |> Repo.update()
    end)
    |> Multi.run(:publish_in_discord, fn %{post: post} ->
      Sanbase.Notifications.Insight.publish_in_discord(post)
    end)
    |> Multi.run(:create_timeline_event, fn %{post: post} ->
      TimelineEvent.create_event(post, %{
        event_type: TimelineEvent.publish_insight(),
        user_id: user_id
      })
    end)
    |> Repo.transaction()
  end

  defp images_cast(changeset, %{image_urls: image_urls}) do
    images = PostImage |> where([i], i.image_url in ^image_urls) |> Repo.all()

    if Enum.any?(images, fn %{post_id: post_id} -> not is_nil(post_id) end) do
      changeset
      |> Ecto.Changeset.add_error(
        :images,
        "The images you are trying to use are already used in another post"
      )
    else
      changeset
      |> put_assoc(:images, images)
    end
  end

  defp images_cast(changeset, _), do: changeset

  defp get_only_published_or_own_posts(posts, user_id) do
    posts
    |> Enum.filter(fn post ->
      post.user_id == user_id || post.ready_state == published()
    end)
  end
end
