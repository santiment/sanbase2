defmodule Sanbase.Auth.UserTest do
  use Sanbase.DataCase, async: false

  import Mockery

  alias Sanbase.Auth.{User, EthAccount}

  test "san balance cache is stale when the cache is never updated" do
    user = %User{san_balance_updated_at: nil, privacy_policy_accepted: true}

    assert User.san_balance_cache_stale?(user)
  end

  test "san balance cache is stale when the san balance was updated 10 min ago" do
    user = %User{
      san_balance_updated_at: Timex.shift(Timex.now(), minutes: -10),
      privacy_policy_accepted: true
    }

    assert User.san_balance_cache_stale?(user)
  end

  test "san balance cache is not stale when the san balance was updated 5 min ago" do
    user = %User{
      san_balance_updated_at: Timex.shift(Timex.now(), minutes: -5),
      privacy_policy_accepted: true
    }

    refute User.san_balance_cache_stale?(user)
  end

  test "update_san_balance_changeset is returning a changeset with updated san balance" do
    mock(Sanbase.InternalServices.Ethauth, :san_balance, Decimal.new(5))

    user = %User{
      san_balance: 0,
      eth_accounts: [%EthAccount{address: "0x000000000001"}],
      privacy_policy_accepted: true
    }

    changeset = User.update_san_balance_changeset(user)

    assert changeset.changes[:san_balance] == Decimal.new(5)
    #
    assert Sanbase.TestUtils.date_close_to(
             Timex.now(),
             changeset.changes[:san_balance_updated_at],
             2,
             :seconds
           )
  end

  test "san_balance! does not update the balance if the balance cache is not stale" do
    user = %User{
      san_balance_updated_at: Timex.now(),
      san_balance: Decimal.new(5),
      privacy_policy_accepted: true
    }

    assert User.san_balance!(user) == Decimal.new(5)
  end

  test "san_balance! updates the balance if the balance cache is stale" do
    user =
      %User{
        san_balance_updated_at: Timex.shift(Timex.now(), minutes: -10),
        salt: User.generate_salt(),
        privacy_policy_accepted: true
      }
      |> Repo.insert!()

    mock(Sanbase.InternalServices.Ethauth, :san_balance, Decimal.new(10))

    %EthAccount{address: "0x000000000001", user_id: user.id}
    |> Repo.insert!()

    user =
      Repo.get(User, user.id)
      |> Repo.preload(:eth_accounts)

    assert User.san_balance!(user) == Decimal.new(10)

    user = Repo.get(User, user.id)

    assert Sanbase.TestUtils.date_close_to(Timex.now(), user.san_balance_updated_at, 2, :seconds)
  end

  test "san_balance! returns test_san_balance if present" do
    user =
      %User{
        san_balance: Decimal.new(10),
        test_san_balance: Decimal.new(20),
        san_balance_updated_at: Timex.shift(Timex.now(), minutes: -2),
        salt: User.generate_salt()
      }
      |> Repo.insert!()

    assert User.san_balance!(user) == Decimal.new(20)
  end

  test "san_balance! returns cached san_balance if test_san_balance not present" do
    user =
      %User{
        san_balance: Decimal.new(10),
        san_balance_updated_at: Timex.shift(Timex.now(), minutes: -2),
        salt: User.generate_salt(),
        privacy_policy_accepted: true
      }
      |> Repo.insert!()

    assert User.san_balance!(user) == Decimal.new(10)
  end

  test "find_or_insert_by_email when the user does not exist" do
    {:ok, user} = User.find_or_insert_by_email("test@example.com", "john_snow")

    assert user.email == "test@example.com"
    assert user.username == "john_snow"
  end

  test "find_or_insert_by_email when the user exists" do
    existing_user =
      %User{
        email: "test@example.com",
        username: "cersei",
        salt: User.generate_salt(),
        privacy_policy_accepted: true
      }
      |> Repo.insert!()

    {:ok, user} = User.find_or_insert_by_email(existing_user.email, "john_snow")

    assert user.id == existing_user.id
    assert user.email == existing_user.email
    assert user.username == existing_user.username
  end

  test "update_email_token updates the email_token and the email_token_generated_at" do
    user =
      %User{salt: User.generate_salt(), privacy_policy_accepted: true}
      |> Repo.insert!()

    {:ok, user} = User.update_email_token(user)

    assert user.email_token != nil

    assert Sanbase.TestUtils.date_close_to(
             Timex.now(),
             user.email_token_generated_at,
             2,
             :seconds
           )
  end

  test "mark_email_token_as_validated updates the email_token_validated_at" do
    user =
      %User{salt: User.generate_salt()}
      |> Repo.insert!()

    {:ok, user} = User.mark_email_token_as_validated(user)

    assert Sanbase.TestUtils.date_close_to(
             Timex.now(),
             user.email_token_validated_at,
             2,
             :seconds
           )
  end

  test "email_token_valid? validates the token properly" do
    user = %User{email_token: "test_token"}
    refute User.email_token_valid?(user, "wrong_token")

    user = %User{
      email_token: "test_token",
      email_token_generated_at: Timex.shift(Timex.now(), days: -2)
    }

    refute User.email_token_valid?(user, "test_token")

    user = %User{
      email_token: "test_token",
      email_token_generated_at: Timex.now(),
      email_token_validated_at: Timex.shift(Timex.now(), minutes: -20)
    }

    refute User.email_token_valid?(user, "test_token")

    user = %User{
      email_token: "test_token",
      email_token_generated_at: Timex.now()
    }

    assert User.email_token_valid?(user, "test_token")
  end
end
