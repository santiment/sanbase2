defmodule SanbaseWeb.Graphql.User.FollowingApiTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers
  import ExUnit.CaptureLog

  alias Sanbase.Auth.User
  alias Sanbase.Repo
  alias Sanbase.Following.UserFollower

  setup do
    user = insert(:user)

    conn = setup_jwt_auth(build_conn(), user)

    {:ok, conn: conn, current_user: user}
  end

  describe "current user following/followers" do
    test "no followers/following", %{conn: conn, current_user: current_user} do
      result =
        current_user_query()
        |> execute_and_handle_success("currentUser", conn)

      assert result == %{"followers" => [], "following" => []}
    end

    test "current user follows another user", %{conn: conn, current_user: current_user} do
      user_to_follow = insert(:user)
      UserFollower.follow(user_to_follow.id, current_user.id)

      result =
        current_user_query()
        |> execute_and_handle_success("currentUser", conn)

      assert result == %{
               "followers" => [],
               "following" => [%{"userId" => "#{user_to_follow.id}"}]
             }
    end

    test "current user is followed by another user", %{conn: conn, current_user: current_user} do
      follower = insert(:user)
      UserFollower.follow(current_user.id, follower.id)

      result =
        current_user_query()
        |> execute_and_handle_success("currentUser", conn)

      assert result == %{
               "followers" => [%{"followerId" => "#{follower.id}"}],
               "following" => []
             }
    end
  end

  describe "follow" do
    test "follow user", %{conn: conn, current_user: current_user} do
      user_to_follow = insert(:user)

      result =
        user_to_follow.id
        |> follow_unfollow_mutation("follow")
        |> execute_follow_unfollow(conn)
        |> get_in(["data", "follow"])

      assert result == %{
               "followers" => [],
               "following" => [%{"userId" => "#{user_to_follow.id}"}]
             }
    end

    test "try following oneself", %{conn: conn, current_user: current_user} do
      result =
        current_user.id
        |> follow_unfollow_mutation("follow")
        |> execute_follow_unfollow(conn)
        |> Map.get("errors")
        |> hd()
        |> Map.get("message")

      assert result == "User can't follow oneself"
    end
  end

  describe "unfollow" do
    test "unfollow followed user", %{conn: conn, current_user: current_user} do
      user_to_follow = insert(:user)
      UserFollower.follow(user_to_follow.id, current_user.id)

      result =
        user_to_follow.id
        |> follow_unfollow_mutation("unfollow")
        |> execute_follow_unfollow(conn)
        |> get_in(["data", "unfollow"])

      assert result == %{"followers" => [], "following" => []}
    end

    test "unfollow not followed", %{conn: conn, current_user: current_user} do
      user_to_follow = insert(:user)

      result =
        user_to_follow.id
        |> follow_unfollow_mutation("unfollow")
        |> execute_follow_unfollow(conn)
        |> Map.get("errors")
        |> hd()
        |> Map.get("message")

      assert result == "Error trying to unfollow user"
    end
  end

  defp follow_unfollow_mutation(user_id, type) do
    """
    mutation {
      #{type}(user_id: "#{user_id}") {
        following {
          userId
        }
        followers {
          followerId
        }
      }
    }
    """
  end

  defp current_user_query() do
    """
    {
      currentUser {
        following {
          userId
        }
        followers {
          followerId
        }
      }
    }
    """
  end

  defp execute_follow_unfollow(mutation, conn) do
    conn
    |> post("/graphql", mutation_skeleton(mutation))
    |> json_response(200)
  end

  defp execute_and_handle_success(query, query_name, conn) do
    conn
    |> post("/graphql", query_skeleton(query, query_name))
    |> json_response(200)
    |> get_in(["data", query_name])
  end
end
