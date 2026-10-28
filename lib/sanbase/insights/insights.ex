defmodule Sanbase.Insights do
  @moduledoc "Entry point to the insights domain for the web layer."

  alias Sanbase.Accounts.User
  alias Sanbase.Insight.{Post, PostPaywall, PostImage, ImageUrl, PopularAuthor, Category}

  defdelegate popular_authors(), to: PopularAuthor, as: :get

  defdelegate user_insights(user_id, opts), to: Post
  defdelegate user_public_insights(user_id, opts), to: Post
  defdelegate public_insights(opts), to: Post
  defdelegate public_insights_by_tags(tags, opts), to: Post
  defdelegate search_published(search_term, opts), to: Post, as: :search_published_insights

  defdelegate related_projects(post), to: Post

  defdelegate filter_paywalled_with_access(posts, auth, opts), to: PostPaywall

  @doc "Published insights are visible to everyone, unpublished ones only to their author."
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

  defdelegate all_tags(), to: Sanbase.Tag, as: :all
  defdelegate all_categories_with_count(), to: Category, as: :all_with_insight_count

  @doc ~s"""
  Images in `text`, in order, with the thumbnail variants of the stored images.
  Stored images missing from the text are appended when `include_db_only_images?`.
  """
  def post_images(%Post{images: images}, text, include_db_only_images?) do
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
      if include_db_only_images?,
        do: Enum.reject(db_images, &MapSet.member?(text_urls, String.downcase(&1.image_url))),
        else: []

    (regex_images ++ orphan_db_images)
    |> Enum.uniq_by(fn %{image_url: url} -> String.downcase(url) end)
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
