defmodule Sanbase.Voting.Post do
  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query

  use Timex.Ecto.Timestamps

  alias Sanbase.Voting.{Poll, Post, Vote, PostImage, Tag}
  alias Sanbase.Auth.User

  @approved "approved"
  @declined "declined"
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
    field(:state, :string)
    field(:moderation_comment, :string)
    field(:ready_state, :string, default: @draft)
    field(:discourse_topic_url, :string)

    has_many(:images, PostImage, on_delete: :delete_all)

    many_to_many(
      :tags,
      Tag,
      join_through: "posts_tags",
      on_replace: :delete,
      on_delete: :delete_all
    )

    timestamps()
  end

  def create_changeset(%Post{} = post, attrs) do
    post
    |> cast(attrs, [:title, :short_desc, :link, :text, :discourse_topic_url])
    |> tags_cast(attrs)
    |> images_cast(attrs)
    |> validate_required([:poll_id, :user_id, :title])
    |> validate_length(:title, max: 140)
    |> unique_constraint(:poll_id, name: :posts_poll_id_title_index)
  end

  def update_changeset(%Post{} = post, attrs) do
    post
    |> cast(attrs, [:title, :short_desc, :link, :text, :discourse_topic_url])
    |> tags_cast(attrs)
    |> images_cast(attrs)
    |> validate_required([:poll_id, :user_id, :title])
    |> validate_length(:title, max: 140)
    |> unique_constraint(:poll_id, name: :posts_poll_id_title_index)
  end

  def publish_changeset(%Post{} = post, attrs) do
    post
    |> cast(attrs, [:ready_state])
  end

  def approved_state(), do: @approved
  def declined_state(), do: @declined

  def published(), do: @published
  def draft(), do: @draft

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

    result = Ecto.Adapters.SQL.query!(Sanbase.Repo, query)

    result.rows
    |> Enum.map(fn row ->
      Sanbase.Repo.load(Post, {result.columns, row})
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

  # Helper functions
  defp tags_cast(changeset, %{tags: tags}) do
    tags = Tag |> where([t], t.name in ^tags) |> Sanbase.Repo.all()

    changeset
    |> put_assoc(:tags, tags)
  end

  defp tags_cast(changeset, _), do: changeset

  defp images_cast(changeset, %{image_urls: image_urls}) do
    images = PostImage |> where([i], i.image_url in ^image_urls) |> Sanbase.Repo.all()

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
