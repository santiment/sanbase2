defmodule Sanbase.Accounts.ProtectedUserTest do
  # async: false — the module backs a global :persistent_term entry that
  # every other test reads. Each test here saves the seed in `setup` and
  # restores it in `on_exit` so cross-file state remains the legacy 1..10
  # range expected by the rest of the suite.
  use Sanbase.DataCase, async: false

  import Ecto.Query, only: [from: 2]
  import Sanbase.Factory

  alias Sanbase.Accounts.{ProtectedUser, User}
  alias Sanbase.Repo

  setup do
    key = ProtectedUser.cache_key()
    original = :persistent_term.get(key, nil)

    on_exit(fn ->
      case original do
        nil -> :persistent_term.erase(key)
        value -> :persistent_term.put(key, value)
      end
    end)

    :ok
  end

  describe "refresh/0" do
    test "reads are_activity_traces_hidden users from the DB and caches them" do
      protected_user = insert(:user, are_activity_traces_hidden: true)
      _other_user = insert(:user)

      ids = ProtectedUser.refresh()

      assert MapSet.member?(ids, protected_user.id)
      assert ProtectedUser.activity_traces_hidden?(protected_user.id)
    end

    test "subsequent reads serve from :persistent_term without querying the DB" do
      protected_user = insert(:user, are_activity_traces_hidden: true)
      ProtectedUser.refresh()

      # Flip the column in the DB; the cache must keep returning the stale
      # value until the TTL expires or refresh/0 is called explicitly.
      Repo.update_all(
        from(u in User, where: u.id == ^protected_user.id),
        set: [are_activity_traces_hidden: false]
      )

      assert ProtectedUser.activity_traces_hidden?(protected_user.id)
    end

    test "expired entry triggers a fresh DB read on next call" do
      protected_user = insert(:user, are_activity_traces_hidden: true)
      ProtectedUser.refresh()
      ProtectedUser.expire_cache_for_test!()

      Repo.update_all(
        from(u in User, where: u.id == ^protected_user.id),
        set: [are_activity_traces_hidden: false]
      )

      refute ProtectedUser.activity_traces_hidden?(protected_user.id)
    end
  end

  describe "activity_traces_hidden?/1" do
    test "returns false for non-integer input even when cache is populated" do
      ProtectedUser.refresh()

      refute ProtectedUser.activity_traces_hidden?(nil)
      refute ProtectedUser.activity_traces_hidden?("1")
      refute ProtectedUser.activity_traces_hidden?(:foo)
    end
  end
end
