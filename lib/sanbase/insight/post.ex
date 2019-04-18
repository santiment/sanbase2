defmodule Sanbase.Insight.Post do
  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query

  use Timex.Ecto.Timestamps

  alias Sanbase.Tag
  alias Sanbase.Insight.{Poll, Post, Vote, PostImage}
  alias Sanbase.Auth.User

  alias Sanbase.Repo

  @preloads [:votes, :user, :images, :tags]
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
    |> cast(attrs, [:ready_state, :discourse_topic_url, :published_at])
  end

  def awaiting_approval_state(), do: @awaiting_approval
  def approved_state(), do: @approved
  def declined_state(), do: @declined

  def published(), do: @published
  def draft(), do: @draft

  def preloads(), do: @preloads

  @doc """
  All insights for given user_id
  """
  def user_insights(user_id) do
    Post
    |> by_user(user_id)
    |> Repo.all()
    |> Repo.preload(@preloads)
  end

  @doc """
  All published insights for given user_id
  """
  def user_public_insights(user_id) do
    published_and_approved_insights()
    |> by_user(user_id)
    |> Repo.all()
    |> Repo.preload(@preloads)
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

  @doc """
  All published and approved insights by given tag and by current_user
  """
  def user_public_insights_by_tag(user_id, tag) do
    published_and_approved_insights()
    |> by_user(user_id)
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
  def change_owner_to_anonymous(user_id) do
    anon_user_id =
      User
      |> Repo.get_by(username: User.insights_fallback_username())
      |> Map.get(:id)

    from(p in Post, where: p.user_id == ^user_id)
    |> Repo.update_all(set: [user_id: anon_user_id])
  end

  # Helper functions

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

  defp published_insights() do
    from(
      p in Post,
      where: p.ready_state == ^@published
    )
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
        "The images you are trying to use are already used in another post"
      )
    else
      changeset
      |> put_assoc(:images, images)
    end
  end

  defp images_cast(changeset, _), do: changeset
end
