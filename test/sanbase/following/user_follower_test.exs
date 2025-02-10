defmodule Sanbase.Accounts.UserFollowerTest do
  use Sanbase.DataCase, async: false

  import Sanbase.Factory

  alias Sanbase.Accounts.UserFollower

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

      following_ids = user.id |> UserFollower.followed_by() |> Enum.map(& &1.id)
      followers_ids = user.id |> UserFollower.followers_of() |> Enum.map(& &1.id)

      assert following_ids == [user2.id]
      assert followers_ids == [user2.id]
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
      followers = UserFollower.followers_of(user.id)

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

      following_ids = user.id |> UserFollower.followed_by() |> Enum.map(& &1.id) |> Enum.sort()
      expected_following_ids = Enum.sort([user2.id, user3.id])
      assert following_ids == expected_following_ids
    end
  end

  describe "#following" do
    test "returns empty list when no users are following", %{user: user} do
      assert UserFollower.followers_of(user.id) == []
    end

    test "returns the list of users following certain user", %{
      user: user,
      user2: user2,
      user3: user3
    } do
      UserFollower.follow(user.id, user2.id)
      UserFollower.follow(user.id, user3.id)

      followers_ids = user.id |> UserFollower.followers_of() |> Enum.map(& &1.id) |> Enum.sort()
      expected_followers_ids = Enum.sort([user2.id, user3.id])
      assert followers_ids == expected_followers_ids
    end
  end
end
