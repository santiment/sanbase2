defmodule Sanbase.Auth.UserTest do
  use Sanbase.DataCase, async: false

  alias Sanbase.Auth.{User, EthAccount}

  test "san balance cache is stale when the cache is never updated" do
    user = %User{san_balance_updated_at: nil}

    assert User.san_balance_cache_stale?(user)
  end

  test "san balance cache is stale when the san balance was updated 10 min ago" do
    user = %User{san_balance_updated_at: Timex.shift(Timex.now(), minutes: -10)}

    assert User.san_balance_cache_stale?(user)
  end

  test "san balance cache is not stale when the san balance was updated 5 min ago" do
    user = %User{san_balance_updated_at: Timex.shift(Timex.now(), minutes: -5)}

    refute User.san_balance_cache_stale?(user)
  end

  test "update_san_balance_changeset is returning a changeset with updated san balance" do
    user = %User{san_balance: 0, eth_accounts: [%EthAccount{address: "0x05"}]}

    changeset = User.update_san_balance_changeset(user)

    assert changeset.changes[:san_balance] == 5
    assert Timex.diff(Timex.now(), changeset.changes[:san_balance_updated_at], :seconds) == 0
  end

  test "san_balance! does not update the balance if the balance cache is not stale" do
    user = %User{san_balance_updated_at: Timex.now(), san_balance: 5}

    assert User.san_balance!(user) == 5
  end

  test "san_balance! updates the balance if the balance cache is stale" do
    user = %User{san_balance_updated_at: Timex.shift(Timex.now(), minutes: -10), salt: User.generate_salt()}
    |> Repo.insert!

    %EthAccount{address: "0x10", user_id: user.id}
    |> Repo.insert!

    user = Repo.get(User, user.id)
    |> Repo.preload(:eth_accounts)

    assert User.san_balance!(user) == 10

    user = Repo.get(User, user.id)
    assert Timex.diff(Timex.now(), user.san_balance_updated_at, :seconds) == 0
  end
end
