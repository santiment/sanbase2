defmodule Sanbase.Insight.PopularAuthor do
  alias Sanbase.Vote
  alias Sanbase.Insight.Post
  alias Sanbase.Auth.{User, UserFollower}

  @doc ~s"""
  Returns a list of `size` number of users, ranked by how popular insights
  authors they are.
  Users
  """
  def get(size \\ 10) do
    post_id_to_votes_map = Vote.post_id_to_votes()
    user_id_to_post_id_list = Post.user_id_to_post_ids_list()
    user_id_to_followers_count_map = UserFollower.user_id_to_followers_count()

    user_id_to_total_votes_map =
      Enum.map(
        user_id_to_post_id_list,
        fn {user_id, post_ids} ->
          total_votes_for_user =
            Enum.map(post_ids, &Map.get(post_id_to_votes_map, &1, 0)) |> Enum.sum()

          {user_id, total_votes_for_user}
        end
      )

    # Popular insight authors are authors that have at least one post.
    # Map over the user to votes map as this is the list of only those users
    # who have created an insight
    user_popularity_score =
      Enum.map(user_id_to_total_votes_map, fn {user_id, total_votes} ->
        followers_count = Map.get(user_id_to_followers_count_map, user_id, 0)
        popularity_score = total_votes * 3 + followers_count * 5
        {user_id, popularity_score}
      end)
      |> Enum.reject(fn {_user_id, score} -> score == 0 end)
      |> Enum.sort_by(fn {_user_id, score} -> score end, :desc)
      |> Enum.take(size)

    user_ids = Enum.map(user_popularity_score, fn {user_id, _score} -> user_id end)

    User.by_id(user_ids)
  end
end
