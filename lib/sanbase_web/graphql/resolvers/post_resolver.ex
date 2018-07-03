defmodule SanbaseWeb.Graphql.Resolvers.PostResolver do
  require Logger

  import Ecto.Query

  alias Sanbase.Auth.User
  alias Sanbase.Voting.{Post, Poll, Tag}
  alias Sanbase.Model.Project
  alias Sanbase.Repo
  alias SanbaseWeb.Graphql.Helpers.Utils

  @preloaded_assoc [:votes, :user, :images, :tags]

  def post(_root, %{id: post_id}, _resolution) do
    case Repo.get(Post, post_id) do
      nil -> {:error, "There is no post with id #{post_id}"}
      post -> {:ok, post}
    end
  end

  def all_insights(_root, _args, %{
        context: %{auth: %{current_user: %User{id: user_id}}}
      }) do
    posts =
      user_id
      |> Post.ranked_published_or_own_posts()
      |> Repo.preload(@preloaded_assoc)

    {:ok, posts}
  end

  def all_insights(_root, _args, _context) do
    posts =
      Post.ranked_published_posts()
      |> Repo.preload(@preloaded_assoc)

    {:ok, posts}
  end

  def all_insights_for_user(_root, %{user_id: user_id}, _context) do
    query =
      from(
        p in Post,
        where: p.user_id == ^user_id
      )

    posts =
      query
      |> Repo.all()
      |> Repo.preload(@preloaded_assoc)

    {:ok, posts}
  end

  def all_insights_user_voted_for(_root, %{user_id: user_id}, _context) do
    query =
      from(
        p in Post,
        where: fragment("? IN (SELECT post_id FROM votes WHERE user_id = ?)", p.id, ^user_id)
      )

    posts =
      query
      |> Repo.all()
      |> Repo.preload(@preloaded_assoc)

    {:ok, posts}
  end

  def all_insights_by_tag(_root, %{tag: tag}, %{
        context: %{auth: %{current_user: %User{id: user_id}}}
      }) do
    posts =
      user_id
      |> Post.ranked_published_or_own_posts()
      |> Repo.preload(@preloaded_assoc)
      |> filter_by_tag(tag)

    {:ok, posts}
  end

  def all_insights_by_tag(_root, %{tag: tag}, _context) do
    posts =
      Post.ranked_published_posts()
      |> Repo.preload(@preloaded_assoc)
      |> filter_by_tag(tag)

    {:ok, posts}
  end

  def related_projects(post, _, _) do
    tags = post.tags |> Enum.map(& &1.name)

    query =
      from(
        p in Project,
        where: p.ticker in ^tags and not is_nil(p.coinmarketcap_id)
      )

    {:ok, Repo.all(query)}
  end

  def create_post(_root, post_args, %{
        context: %{auth: %{current_user: user}}
      }) do
    %Post{user_id: user.id, poll_id: Poll.find_or_insert_current_poll!().id}
    |> Post.create_changeset(post_args)
    |> Repo.insert()
    |> case do
      {:ok, post} ->
        {:ok, post}

      {:error, changeset} ->
        {
          :error,
          message: "Can't create post", details: Utils.error_details(changeset)
        }
    end
  end

  def update_post(_root, %{id: post_id} = post_args, %{
        context: %{auth: %{current_user: %User{id: user_id}}}
      }) do
    draft_state = Post.draft()
    published_state = Post.published()

    case Repo.get(Post, post_id) do
      %Post{user_id: ^user_id, ready_state: ^draft_state} = post ->
        post
        |> Repo.preload([:tags, :images])
        |> Post.update_changeset(post_args)
        |> Repo.update()
        |> case do
          {:ok, post} ->
            {:ok, post}

          {:error, changeset} ->
            {
              :error,
              message: "Can't update post", details: Utils.error_details(changeset)
            }
        end

      %Post{user_id: another_user_id} when user_id != another_user_id ->
        {:error, "Cannot update not owned post: #{post_id}"}

      %Post{user_id: ^user_id, ready_state: ^published_state} ->
        {:error, "Cannot update published post: #{post_id}"}

      _post ->
        {:error, "Cannot update post with id: #{post_id}"}
    end
  end

  def delete_post(_root, %{id: post_id}, %{
        context: %{auth: %{current_user: %User{id: user_id}}}
      }) do
    case Repo.get(Post, post_id) do
      %Post{user_id: ^user_id} = post ->
        # Delete the images from the S3/Local store.
        delete_post_images(post)

        # Note: When ecto changeset middleware is implemented return just `Repo.delete(post)`
        case Repo.delete(post) do
          {:ok, post} ->
            {:ok, post}

          {:error, changeset} ->
            {
              :error,
              message: "Can't delete post with id #{post_id}",
              details: Utils.error_details(changeset)
            }
        end

      _post ->
        {:error, "You don't own the post with id #{post_id}"}
    end
  end

  def all_tags(_root, _args, _context) do
    {:ok, Repo.all(Tag)}
  end

  def publish_insight(_root, %{id: post_id}, %{
        context: %{auth: %{current_user: %User{id: user_id}}}
      }) do
    case Repo.get(Post, post_id) do
      %Post{user_id: ^user_id} = post ->
        post
        |> Post.publish_changeset(%{ready_state: Post.published()})
        |> Repo.update()
        |> case do
          {:ok, post} ->
            {:ok, post}

          {:error, changeset} ->
            {
              :error,
              message: "Can't publish post with id #{post_id}",
              details: Utils.error_details(changeset)
            }
        end

      _post ->
        {:error, "Cannot change ready_state of post with id: #{post_id}"}
    end
  end

  # Helper functions

  defp delete_post_images(%Post{} = post) do
    extract_image_url_from_post(post)
    |> Enum.map(&Sanbase.FileStore.delete/1)
  end

  defp extract_image_url_from_post(%Post{} = post) do
    post
    |> Repo.preload(:images)
    |> Map.get(:images, [])
    |> Enum.map(fn %{image_url: image_url} -> image_url end)
  end

  defp filter_by_tag(posts, tag) do
    posts
    |> Enum.filter(fn post ->
      tag in Enum.map(post.tags, & &1.name)
    end)
  end
end
