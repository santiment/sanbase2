defmodule Sanbase.AppNotifications.NotificationMutedUserTest do
  use Sanbase.DataCase, async: true

  import Sanbase.Factory

  alias Sanbase.AppNotifications.NotificationMutedUser

  describe "mute/2" do
    test "mutes a user" do
      user = insert(:user)
      muted = insert(:user)

      assert {:ok, %NotificationMutedUser{}} = NotificationMutedUser.mute(user.id, muted.id)
    end

    test "returns error when muting self" do
      user = insert(:user)

      assert {:error, "Cannot mute yourself"} = NotificationMutedUser.mute(user.id, user.id)
    end

    test "returns error when muting same user twice" do
      user = insert(:user)
      muted = insert(:user)

      assert {:ok, _} = NotificationMutedUser.mute(user.id, muted.id)
      assert {:error, %Ecto.Changeset{}} = NotificationMutedUser.mute(user.id, muted.id)
    end
  end

  describe "unmute/2" do
    test "unmutes a previously muted user" do
      user = insert(:user)
      muted = insert(:user)

      {:ok, _} = NotificationMutedUser.mute(user.id, muted.id)
      assert {:ok, %NotificationMutedUser{}} = NotificationMutedUser.unmute(user.id, muted.id)
    end

    test "returns error when user is not muted" do
      user = insert(:user)
      other = insert(:user)

      assert {:error, "User is not muted"} = NotificationMutedUser.unmute(user.id, other.id)
    end
  end

  describe "list_muted_users/1" do
    test "returns muted users" do
      user = insert(:user)
      muted1 = insert(:user)
      muted2 = insert(:user)

      {:ok, _} = NotificationMutedUser.mute(user.id, muted1.id)
      {:ok, _} = NotificationMutedUser.mute(user.id, muted2.id)

      result = NotificationMutedUser.list_muted_users(user.id)
      result_ids = Enum.map(result, & &1.id) |> Enum.sort()

      assert result_ids == Enum.sort([muted1.id, muted2.id])
    end

    test "returns empty list when no users are muted" do
      user = insert(:user)
      assert NotificationMutedUser.list_muted_users(user.id) == []
    end

    test "does not return users muted by other users" do
      user = insert(:user)
      other = insert(:user)
      muted = insert(:user)

      {:ok, _} = NotificationMutedUser.mute(other.id, muted.id)

      assert NotificationMutedUser.list_muted_users(user.id) == []
    end
  end

  describe "user_ids_that_muted/1" do
    test "returns user IDs that have muted the given user" do
      actor = insert(:user)
      muter1 = insert(:user)
      muter2 = insert(:user)

      {:ok, _} = NotificationMutedUser.mute(muter1.id, actor.id)
      {:ok, _} = NotificationMutedUser.mute(muter2.id, actor.id)

      result = NotificationMutedUser.user_ids_that_muted(actor.id)

      assert MapSet.equal?(result, MapSet.new([muter1.id, muter2.id]))
    end

    test "returns empty MapSet when no one has muted the user" do
      actor = insert(:user)

      assert NotificationMutedUser.user_ids_that_muted(actor.id) == MapSet.new()
    end
  end
end
