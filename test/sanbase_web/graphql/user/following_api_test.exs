defmodule SanbaseWeb.Graphql.User.FollowingApiTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  alias Sanbase.Accounts.UserFollower

  setup do
    user = insert(:user)

    conn = setup_jwt_auth(build_conn(), user)

    {:ok, conn: conn, current_user: user}
  end

  describe "current user following/followers lists" do
    test "when no followers/following - returns empty lists", %{conn: conn} do
      result = execute_query(conn, current_user_query(), "currentUser")

      assert result == %{
               "followers" => %{"count" => 0, "users" => []},
               "following" => %{"count" => 0, "users" => []}
             }
    end

    test "when following another user - following list includes users that he follows",
         %{conn: conn, current_user: current_user} do
      user_to_follow = insert(:user)
      UserFollower.follow(user_to_follow.id, current_user.id)

      result = execute_query(conn, current_user_query(), "currentUser")

      assert result == %{
               "followers" => %{"count" => 0, "users" => []},
               "following" => %{"count" => 1, "users" => [%{"id" => "#{user_to_follow.id}"}]}
             }
    end

    test "when current user is followed by another user - followers list includes user's followers",
         %{conn: conn, current_user: current_user} do
      follower = insert(:user)
      UserFollower.follow(current_user.id, follower.id)

      result = execute_query(conn, current_user_query(), "currentUser")

      assert result == %{
               "followers" => %{"count" => 1, "users" => [%{"id" => "#{follower.id}"}]},
               "following" => %{"count" => 0, "users" => []}
             }
    end
  end

  describe "current user following2/followers2 lists" do
    test "when no followers/following - returns empty lists", %{conn: conn} do
      result = execute_query(conn, current_user_query2(), "currentUser")

      assert result == %{
               "followers2" => %{"count" => 0, "users" => []},
               "following2" => %{"count" => 0, "users" => []}
             }
    end

    test "when following another user - following list includes users that he follows",
         %{conn: conn, current_user: current_user} do
      user_to_follow = insert(:user)
      UserFollower.follow(user_to_follow.id, current_user.id)

      result = execute_query(conn, current_user_query2(), "currentUser")

      assert result == %{
               "followers2" => %{"count" => 0, "users" => []},
               "following2" => %{
                 "count" => 1,
                 "users" => [
                   %{
                     "isNotificationDisabled" => false,
                     "user" => %{"id" => "#{user_to_follow.id}"}
                   }
                 ]
               }
             }
    end

    test "when current user is followed by another user - followers list includes user's followers",
         %{conn: conn, current_user: current_user} do
      follower = insert(:user)
      UserFollower.follow(current_user.id, follower.id)

      result = execute_query(conn, current_user_query2(), "currentUser")

      assert result == %{
               "followers2" => %{
                 "count" => 1,
                 "users" => [
                   %{"isNotificationDisabled" => false, "user" => %{"id" => "#{follower.id}"}}
                 ]
               },
               "following2" => %{"count" => 0, "users" => []}
             }
    end
  end

  describe "#follow" do
    test "can follow user", %{conn: conn} do
      user_to_follow = insert(:user)

      result = execute_mutation(conn, follow_mutation(user_to_follow.id), "follow")

      assert result == %{
               "followers2" => %{"count" => 0, "users" => []},
               "following2" => %{
                 "count" => 1,
                 "users" => [
                   %{
                     "isNotificationDisabled" => false,
                     "user" => %{"id" => "#{user_to_follow.id}"}
                   }
                 ]
               }
             }
    end

    test "can't follow himself", %{conn: conn, current_user: current_user} do
      result = execute_mutation_with_error(conn, follow_mutation(current_user.id))

      assert result == "User can't follow oneself"
    end

    test "mutation can be called only by logged in users" do
      # not logged in user
      conn = build_conn()
      user = insert(:user)

      result = execute_mutation_with_error(conn, follow_mutation(user.id))

      assert result == "unauthorized"
    end
  end

  describe "#unfollow" do
    test "can unfollow already followed user", %{conn: conn, current_user: current_user} do
      user_to_follow = insert(:user)
      UserFollower.follow(user_to_follow.id, current_user.id)

      result = execute_mutation(conn, unfollow_mutation(user_to_follow.id), "unfollow")

      assert result == %{
               "followers2" => %{"count" => 0, "users" => []},
               "following2" => %{"count" => 0, "users" => []}
             }
    end

    test "can't unfollow user that has not been followed", %{conn: conn, current_user: user} do
      user_to_follow = insert(:user)

      result = execute_mutation_with_error(conn, unfollow_mutation(user_to_follow.id))

      assert result ==
               "User with id #{user_to_follow.id} is not followed by user with id #{user.id}"
    end
  end

  describe "#followingToggelNotification" do
    test "disable notification", %{conn: conn, current_user: current_user} do
      user_to_follow = insert(:user)
      UserFollower.follow(user_to_follow.id, current_user.id)

      result =
        execute_mutation(
          conn,
          following_toggle_notification(user_to_follow.id, true),
          "followingToggleNotification"
        )

      assert result == %{
               "followers2" => %{"count" => 0, "users" => []},
               "following2" => %{
                 "count" => 1,
                 "users" => [
                   %{
                     "isNotificationDisabled" => true,
                     "user" => %{"id" => "#{user_to_follow.id}"}
                   }
                 ]
               }
             }
    end

    test "disabling notification for not followed user returns error", %{conn: conn} do
      user_to_follow = insert(:user)

      error =
        execute_mutation_with_error(conn, following_toggle_notification(user_to_follow.id, true))

      assert error =~ "This user is not followed!"
    end
  end

  defp follow_mutation(user_id) do
    """
    mutation {
      follow(user_id: "#{user_id}") {
        following2 {
          count
          users {
            user { id }
            isNotificationDisabled
          }
        }
        followers2 {
          count
          users {
            user { id }
            isNotificationDisabled
          }
        }
      }
    }
    """
  end

  defp unfollow_mutation(user_id) do
    """
    mutation {
      unfollow(user_id: "#{user_id}") {
        following2 {
          count
          users {
            user { id }
            isNotificationDisabled
          }
        }
        followers2 {
          count
          users {
            user { id }
            isNotificationDisabled
          }
        }
      }
    }
    """
  end

  defp following_toggle_notification(user_id, disable_notifications) do
    """
    mutation {
      followingToggleNotification(user_id: "#{user_id}", disable_notifications: #{disable_notifications}) {
        following2 {
          count
          users {
            user { id }
            isNotificationDisabled
          }
        }
        followers2 {
          count
          users {
            user { id }
            isNotificationDisabled
          }
        }
      }
    }
    """
  end

  defp current_user_query do
    """
    {
      currentUser {
        following {
          count
          users { id }
        }
        followers {
          count
          users { id }
        }
      }
    }
    """
  end

  defp current_user_query2 do
    """
    {
      currentUser {
        following2 {
          count
          users {
            user {id}
            isNotificationDisabled
          }
        }
        followers2 {
          count
          users {
            user { id }
            isNotificationDisabled
          }
        }
      }
    }
    """
  end
end
