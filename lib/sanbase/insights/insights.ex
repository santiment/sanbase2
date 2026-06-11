defmodule Sanbase.Insights do
  @moduledoc ~s"""
  Public façade for the insights domain. The web/transport layer should call
  only this module rather than reaching into `Sanbase.Insight.Post` and the
  surrounding helpers directly.
  """

  alias Sanbase.Accounts.User
  alias Sanbase.Insight.{Post, PostImage, ImageUrl, PopularAuthor, Category}

  @empty_count_map %{total_count: 0, draft_count: 0, pulse_count: 0, paywall_count: 0}

  @doc "Default zeroed insights-count map used when dataloader has no entry."
  @spec empty_insights_count() :: map()
  def empty_insights_count, do: @empty_count_map

  @doc "Top insight authors with their counts."
  defdelegate popular_authors(), to: PopularAuthor, as: :get

  defdelegate user_insights(user_id, opts), to: Post
  defdelegate user_public_insights(user_id, opts), to: Post
  defdelegate public_insights(opts), to: Post
  defdelegate public_insights_by_tags(tags, opts), to: Post
  defdelegate search_published(search_term, opts), to: Post, as: :search_published_insights
  defdelegate user_voted_insights(user_id, opts), to: Post, as: :all_insights_user_voted_for

  defdelegate related_projects(post), to: Post

  @doc "Pulse insights expose their text via this field; non-pulse insights get nil."
  @spec pulse_text(Post.t()) :: {:ok, String.t() | nil}
  def pulse_text(%Post{} = post) do
    if Post.pulse?(post), do: {:ok, post.text}, else: {:ok, nil}
  end

  @doc ~s"""
  Fetch an insight visible to `viewer_user_id`. Approved-and-published posts
  are visible to everyone; owners always see their own drafts/unpublished
  posts. Returns the same shape `Post.by_id/2` would.
  """
  @spec get_post(non_neg_integer(), non_neg_integer() | nil) ::
          {:ok, Post.t()} | {:error, String.t() | any()}
  def get_post(post_id, viewer_user_id) do
    case Post.by_id(post_id, []) do
      {:ok, %Post{state: "approved", ready_state: "published"} = post} ->
        {:ok, post}

      {:ok, %Post{user_id: ^viewer_user_id} = post} when not is_nil(viewer_user_id) ->
        {:ok, post}

      {:ok, _} ->
        {:error,
         "Insight with id #{post_id} does not exist, is not published, or is not approved"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc ~s"""
  Create a post if the author has not exceeded their daily rate limit. Returns
  `{:error, message}` if the limit is hit, otherwise forwards to `Post.create/2`.
  """
  @spec create_post(User.t(), map()) :: {:ok, Post.t()} | {:error, any()}
  def create_post(%User{} = user, args) do
    case Post.has_not_reached_rate_limits?(user.id) do
      {:ok, _} -> Post.create(user, args)
      {:error, error} -> {:error, error}
    end
  end

  defdelegate update_post(post_id, user, args), to: Post, as: :update
  defdelegate delete_post(post_id, user), to: Post, as: :delete
  defdelegate publish(post_id, user_id), to: Post
  defdelegate create_chart_event(user_id, args), to: Post

  @doc "All tags used across published insights."
  def all_tags, do: Sanbase.Tag.all()

  @doc "All insight categories with the count of published insights in each."
  defdelegate all_categories_with_count(), to: Category, as: :all_with_insight_count

  @doc ~s"""
  Resolve the full ordered list of images for an insight: regex-extract image
  URLs from the post body (preserving in-text order and preferring those URLs),
  enriched with thumbnail variants from `PostImage` rows when available, and
  followed by any DB-only images that no longer appear in the text.
  """
  @spec resolve_post_images(Post.t()) :: {:ok, [map()]}
  def resolve_post_images(%Post{text: text, images: images}) do
    db_images =
      case images do
        list when is_list(list) -> Enum.map(list, &post_image_to_map/1)
        _ -> []
      end

    db_image_by_url = Map.new(db_images, fn img -> {String.downcase(img.image_url), img} end)

    regex_images =
      text
      |> ImageUrl.extract_from_text()
      |> Enum.map(fn url ->
        case Map.get(db_image_by_url, String.downcase(url)) do
          nil -> %{image_url: url}
          db_img -> %{db_img | image_url: url}
        end
      end)

    text_urls = MapSet.new(regex_images, fn %{image_url: url} -> String.downcase(url) end)

    orphan_db_images =
      Enum.reject(db_images, fn %{image_url: url} ->
        MapSet.member?(text_urls, String.downcase(url))
      end)

    all_images =
      (regex_images ++ orphan_db_images)
      |> Enum.uniq_by(fn %{image_url: url} -> String.downcase(url) end)

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
end
