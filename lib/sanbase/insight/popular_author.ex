defmodule Sanbase.Insight.PopularAuthor do
  alias Sanbase.Vote
  alias Sanbase.Insight.Post
  alias Sanbase.Accounts.{User, UserFollower}

  @doc ~s"""
  Returns a list of `size` number of users, ranked by how popular insights
  authors they are.
  Users
  """
  def get(size \\ 10) do
    user_id_to_post_ids_map = Post.Stats.user_id_to_post_ids()

    user_id_stats_map = %{
      to_post_ids_map: user_id_to_post_ids_map,
      to_followers_count_map: UserFollower.user_id_to_followers_count(),
      to_total_votes_map: user_id_to_total_votes_map(user_id_to_post_ids_map),
      to_total_comments_map: user_id_to_total_comments_map(user_id_to_post_ids_map)
    }

    # Popular insight authors are authors that have at least one post.
    # Map over the user to votes map as this is the list of only those users
    # who have created an insight. A small
    user_ids =
      Enum.map(user_id_stats_map.to_total_votes_map, fn {user_id, _total_votes} ->
        popularity_score = compute_author_popularity_score(user_id, user_id_stats_map)

        {user_id, popularity_score}
      end)
      |> Enum.reject(fn {_user_id, score} -> score == 0 end)
      |> Enum.sort_by(fn {_user_id, score} -> score end, :desc)
      |> Enum.take(size)
      |> Enum.map(fn {user_id, _score} -> user_id end)

    # User.by_ids/1 preserves the order of the users as specified in the user_ids list
    User.by_id(user_ids)
  end

  # Private functions

  defp compute_author_popularity_score(user_id, %{} = user_id_stats_map) do
    followers_count = Map.get(user_id_stats_map.to_followers_count_map, user_id, 0)
    insights_count = Map.get(user_id_stats_map.to_post_ids_map, user_id, []) |> length()
    comments_count = Map.get(user_id_stats_map.to_total_comments_map, user_id, 0)
    total_votes = Map.get(user_id_stats_map.to_total_votes_map, user_id, 0)

    total_votes * 3 +
      comments_count * 4 +
      followers_count * 5 +
      Enum.min([5, insights_count])
  end

  defp user_id_to_total_votes_map(user_id_to_post_ids_map) do
    post_id_to_votes_map = Vote.post_id_to_votes()

    Enum.into(
      user_id_to_post_ids_map,
      %{},
      fn {user_id, post_ids} ->
        total_votes_for_user =
          Enum.map(post_ids, &Map.get(post_id_to_votes_map, &1, 0)) |> Enum.sum()

        {user_id, total_votes_for_user}
      end
    )
  end

  defp user_id_to_total_comments_map(user_id_to_post_ids_map) do
    post_id_to_comments_count_map = Post.Stats.post_id_to_comments_count()

    Enum.into(
      user_id_to_post_ids_map,
      %{},
      fn {user_id, post_ids} ->
        total_comments_for_user =
          Enum.map(post_ids, &Map.get(post_id_to_comments_count_map, &1, 0)) |> Enum.sum()

        {user_id, total_comments_for_user}
      end
    )
  end
end
