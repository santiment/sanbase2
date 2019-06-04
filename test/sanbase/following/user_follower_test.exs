defmodule Sanbase.Following.UserFollowerTest do
  use Sanbase.DataCase, async: false

  import Sanbase.Factory

  alias Sanbase.Following.UserFollower

  setup do
    user = insert(:user)
    user2 = insert(:user)
    user3 = insert(:user)

    [
      user: user,
      user2: user2,
      user3: user3
    ]
  end

  describe "#follow" do
    test "changes list of following/followers", %{
      user: user,
      user2: user2
    } do
      UserFollower.follow(user2.id, user.id)
      UserFollower.follow(user.id, user2.id)

      following = UserFollower.followed_by(user.id)
      followers = UserFollower.following(user.id)

      assert following == [user2.id]
      assert followers == [user2.id]
    end
  end

  describe "#unfollow" do
    test "changes list of following/followers", %{
      user: user,
      user2: user2
    } do
      UserFollower.follow(user2.id, user.id)
      UserFollower.follow(user.id, user2.id)

      UserFollower.unfollow(user2.id, user.id)
      UserFollower.unfollow(user.id, user2.id)

      following = UserFollower.followed_by(user.id)
      followers = UserFollower.following(user.id)

      assert following == []
      assert followers == []
    end
  end

  describe "#followed_by" do
    test "returns empty list when no users are followed", %{user: user} do
      assert UserFollower.followed_by(user.id) == []
    end

    test "returns the list of followed users by certain user", %{
      user: user,
      user2: user2,
      user3: user3
    } do
      UserFollower.follow(user2.id, user.id)
      UserFollower.follow(user3.id, user.id)

      assert UserFollower.followed_by(user.id) == [user2.id, user3.id]
    end
  end

  describe "#following" do
    test "returns empty list when no users are following", %{user: user} do
      assert UserFollower.following(user.id) == []
    end

    test "returns the list of users following certain user", %{
      user: user,
      user2: user2,
      user3: user3
    } do
      UserFollower.follow(user.id, user2.id)
      UserFollower.follow(user.id, user3.id)

      assert UserFollower.following(user.id) == [user2.id, user3.id]
    end
  end
end
