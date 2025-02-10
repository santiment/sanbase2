defmodule SanbaseWeb.Graphql.PopularInsightAuthorApiTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  alias Sanbase.Accounts.UserFollower
  alias Sanbase.Vote

  setup do
    [user1, user2, user3, user4, user5, user6] = for _ <- 1..6, do: insert(:user)

    post1 = insert(:published_post, user: user1)
    post2 = insert(:published_post, user: user2)
    post3 = insert(:published_post, user: user2)
    post4 = insert(:published_post, user: user2)
    post5 = insert(:published_post, user: user2)
    _post6 = insert(:published_post, user: user4)
    _post7 = insert(:published_post, user: user5)

    Vote.create(%{post_id: post1.id, user_id: user2.id})
    Vote.create(%{post_id: post1.id, user_id: user3.id})
    Vote.create(%{post_id: post2.id, user_id: user2.id})
    Vote.create(%{post_id: post3.id, user_id: user4.id})
    Vote.create(%{post_id: post4.id, user_id: user1.id})
    Vote.create(%{post_id: post4.id, user_id: user5.id})
    Vote.create(%{post_id: post5.id, user_id: user6.id})

    UserFollower.follow(user1.id, user2.id)
    UserFollower.follow(user2.id, user1.id)
    UserFollower.follow(user3.id, user1.id)
    UserFollower.follow(user4.id, user1.id)
    UserFollower.follow(user5.id, user1.id)
    UserFollower.follow(user5.id, user2.id)
    UserFollower.follow(user2.id, user5.id)

    conn = setup_jwt_auth(build_conn(), user1)

    %{conn: conn, user1: user1, user2: user2, user4: user4, user5: user5}
  end

  test "get popular insight authors", context do
    %{conn: conn, user1: user1, user2: user2, user4: user4, user5: user5} = context
    popular_authors = popular_authors(conn)

    expected_result = [
      %{"id" => to_string(user2.id)},
      %{"id" => to_string(user1.id)},
      %{"id" => to_string(user5.id)},
      %{"id" => to_string(user4.id)}
    ]

    assert popular_authors == expected_result
  end

  defp popular_authors(conn) do
    query = """
    {
      popularInsightAuthors{
        id
      }
    }
    """

    conn
    |> post("/graphql", query_skeleton(query))
    |> json_response(200)
    |> get_in(["data", "popularInsightAuthors"])
  end
end
