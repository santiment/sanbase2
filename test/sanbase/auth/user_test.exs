defmodule Sanbase.Auth.UserTest do
  use Sanbase.DataCase, async: false

  import Mockery
  import Sanbase.Factory
  import ExUnit.CaptureLog

  alias Sanbase.Auth.{User, EthAccount}
  alias Sanbase.Repo

  test "san balance cache is stale when the cache is never updated" do
    user = insert(:user, %{san_balance: nil, san_balance_updated_at: nil})

    assert User.san_balance_cache_stale?(user)
  end

  test "san balance cache is stale when the san balance was updated 10 min ago" do
    user =
      insert(:user,
        san_balance_updated_at: Timex.shift(Timex.now(), minutes: -10),
        privacy_policy_accepted: true
      )

    assert User.san_balance_cache_stale?(user)
  end

  test "san balance cache is not stale when the san balance was updated 5 min ago" do
    user =
      insert(:user,
        san_balance_updated_at: Timex.shift(Timex.now(), minutes: -5),
        privacy_policy_accepted: true
      )

    refute User.san_balance_cache_stale?(user)
  end

  test "update_san_balance_changeset is returning a changeset with updated san balance" do
    mock(Sanbase.InternalServices.Ethauth, :san_balance, {:ok, 5.0})

    user =
      insert(:user,
        eth_accounts: [%EthAccount{address: "0x000000000001"}],
        san_balance: 100,
        san_balance_updated_at: ~N[2020-01-01 00:00:00]
      )

    changeset = User.update_san_balance_changeset(user)

    assert changeset.changes[:san_balance] == 5.0

    assert Sanbase.TestUtils.datetime_close_to(
             NaiveDateTime.utc_now(),
             changeset.changes[:san_balance_updated_at],
             2,
             :seconds
           )
  end

  test "san_balance! returns cached result when EthAccount.san_balance fails" do
    mock(Sanbase.InternalServices.Ethauth, :san_balance, {:error, "foo"})

    user =
      insert(:user,
        san_balance: Decimal.new(100),
        eth_accounts: [%EthAccount{address: "0x000000000001"}],
        privacy_policy_accepted: true
      )

    capture_log(fn ->
      assert User.san_balance!(user) == 100.0
    end)
  end

  test "san_balance! does not update the balance if the balance cache is not stale" do
    user =
      insert(:user,
        san_balance_updated_at: Timex.now(),
        san_balance: Decimal.new(5),
        privacy_policy_accepted: true
      )

    assert User.san_balance!(user) == 5.0
  end

  test "san_balance! updates the balance if the balance cache is stale" do
    user =
      insert(:user,
        san_balance_updated_at: Timex.shift(Timex.now(), minutes: -10),
        privacy_policy_accepted: true
      )

    mock(Sanbase.InternalServices.Ethauth, :san_balance, {:ok, 10.0})

    %EthAccount{address: "0x000000000001", user_id: user.id}
    |> Repo.insert!()

    user =
      Repo.get(User, user.id)
      |> Repo.preload(:eth_accounts)

    assert User.san_balance!(user) == 10.0

    user = Repo.get(User, user.id)

    assert Sanbase.TestUtils.datetime_close_to(
             Timex.now(),
             user.san_balance_updated_at,
             2,
             :seconds
           )
  end

  test "san_balance! returns test_san_balance if present" do
    user =
      insert(:user,
        san_balance: Decimal.new(10),
        test_san_balance: Decimal.new(20),
        san_balance_updated_at: Timex.shift(Timex.now(), minutes: -2)
      )

    assert User.san_balance!(user) == 20.0
  end

  test "san_balance! returns cached san_balance if test_san_balance not present" do
    user =
      insert(:user,
        san_balance: Decimal.new(10),
        san_balance_updated_at: Timex.shift(Timex.now(), minutes: -2),
        privacy_policy_accepted: true
      )

    assert User.san_balance!(user) == 10.0
  end

  test "find_or_insert_by_email when the user does not exist" do
    {:ok, user} = User.find_or_insert_by_email("test@example.com", "john_snow")

    assert user.email == "test@example.com"
    assert user.username == "john_snow"
    assert user.first_login
  end

  test "find_or_insert_by_email when the user exists" do
    existing_user =
      insert(:user,
        email: "test@example.com",
        username: "cersei",
        privacy_policy_accepted: true
      )

    {:ok, user} = User.find_or_insert_by_email(existing_user.email, "john_snow")

    assert user.id == existing_user.id
    assert user.email == existing_user.email
    assert user.username == existing_user.username
  end

  test "update_email_token updates the email_token and the email_token_generated_at" do
    {:ok, user} =
      insert(:user, privacy_policy_accepted: true)
      |> User.update_email_token()

    assert user.email_token != nil

    assert Sanbase.TestUtils.datetime_close_to(
             Timex.now(),
             user.email_token_generated_at,
             2,
             :seconds
           )
  end

  test "mark_email_token_as_validated updates the email_token_validated_at" do
    {:ok, user} =
      insert(:user)
      |> User.mark_email_token_as_validated()

    assert Sanbase.TestUtils.datetime_close_to(
             Timex.now(),
             user.email_token_validated_at,
             2,
             :seconds
           )
  end

  test "email_token_valid? validates the token properly" do
    user = build(:user, email_token: "test_token")
    refute User.email_token_valid?(user, "wrong_token")

    user =
      build(:user,
        email_token: "test_token",
        email_token_generated_at: Timex.shift(Timex.now(), days: -2)
      )

    refute User.email_token_valid?(user, "test_token")

    user =
      build(:user,
        email_token: "test_token",
        email_token_generated_at: Timex.now(),
        email_token_validated_at: Timex.shift(Timex.now(), minutes: -20)
      )

    refute User.email_token_valid?(user, "test_token")

    user =
      build(:user,
        email_token: "test_token",
        email_token_generated_at: Timex.now()
      )

    assert User.email_token_valid?(user, "test_token")
  end

  test "find_by_email_candidate when the user does not exist" do
    {:error, message} = User.find_by_email_candidate("test@example.com", "some token")

    assert message == "Can't find user with email candidate test@example.com"
  end

  test "find_by_email_candidate when the user exists" do
    {:ok, existing_user} =
      insert(:user,
        email: "test@example.com",
        privacy_policy_accepted: true
      )
      |> User.update_email_candidate("test+foo@santiment.net")

    {:ok, user} =
      User.find_by_email_candidate(
        existing_user.email_candidate,
        existing_user.email_candidate_token
      )

    assert user.id == existing_user.id
    assert user.email_candidate == existing_user.email_candidate
  end

  test "find_by_email_candidate when there are two users with the same email_candidate" do
    insert(:user,
      email: "test_first@example.com",
      privacy_policy_accepted: true
    )
    |> User.update_email_candidate("test+foo@santiment.net")

    {:ok, existing_user} =
      insert(:user,
        email: "test@example.com",
        privacy_policy_accepted: true
      )
      |> User.update_email_candidate("test+foo@santiment.net")

    {:ok, user} =
      User.find_by_email_candidate(
        existing_user.email_candidate,
        existing_user.email_candidate_token
      )

    assert user.id == existing_user.id
    assert user.email_candidate == existing_user.email_candidate
  end

  test "update_email_candidate updates the email_candidate, email_candidate_token, email_candidate_token_generated_at and email_candidate_token_validated_at" do
    user = insert(:user, privacy_policy_accepted: true)

    email_candidate = "test+foo@santiment.net"
    {:ok, user} = User.update_email_candidate(user, email_candidate)

    assert user.email_candidate == email_candidate
    assert user.email_candidate_token != nil
    assert user.email_candidate_token_validated_at == nil

    assert Sanbase.TestUtils.datetime_close_to(
             Timex.now(),
             user.email_candidate_token_generated_at,
             2,
             :seconds
           )
  end

  test "update_email_from_email_candidate updates the email with the email_candidate" do
    email_candidate = "test+foo@santiment.net"

    {:ok, user} =
      insert(:user,
        email: "test@example.com",
        privacy_policy_accepted: true
      )
      |> User.update_email_candidate(email_candidate)

    {:ok, user} = User.update_email_from_email_candidate(user)

    assert user.email == email_candidate
    assert user.email_candidate == nil

    assert Sanbase.TestUtils.datetime_close_to(
             Timex.now(),
             user.email_candidate_token_validated_at,
             2,
             :seconds
           )
  end

  test "email_candidate_token_valid? validates the email_candidate_token properly" do
    user = build(:user, email_candidate_token: "test_token")
    refute User.email_candidate_token_valid?(user, "wrong_token")

    user =
      build(:user,
        email_candidate_token: "test_token",
        email_candidate_token_generated_at: Timex.shift(Timex.now(), days: -2)
      )

    refute User.email_candidate_token_valid?(user, "test_token")

    user =
      build(:user,
        email_candidate_token: "test_token",
        email_candidate_token_generated_at: Timex.now(),
        email_candidate_token_validated_at: Timex.shift(Timex.now(), minutes: -20)
      )

    refute User.email_candidate_token_valid?(user, "test_token")

    user =
      build(:user,
        email_candidate_token: "test_token",
        email_candidate_token_generated_at: Timex.now()
      )

    assert User.email_candidate_token_valid?(user, "test_token")
  end

  test "return error on insert/update username with non ascii" do
    user = insert(:user)

    {:error, changeset} =
      User.changeset(user, %{username: "周必聪"})
      |> Repo.update()

    refute changeset.valid?

    assert errors_on(changeset)[:username] |> Enum.at(0) ==
             "Username can contain only latin letters and numbers"
  end

  test "trim whitespace on username" do
    user = insert(:user)

    {:ok, user} =
      User.changeset(user, %{username: " portokala "})
      |> Repo.update()

    assert user.username == "portokala"
  end

  test "converts email and email_candidate to lower case and trims whitespaces" do
    user = insert(:user)

    {:ok, user} =
      User.changeset(user, %{
        email: "  tesT+eMAil@saNTIment.nEt    ",
        email_candidate: " TEst+eMAil_cANDIdate@sanTIMent.NEt    "
      })
      |> Repo.update()

    assert user.email == "test+email@santiment.net"
    assert user.email_candidate == "test+email_candidate@santiment.net"
  end

  test "return error on insert/update email_candidate with an email of another user" do
    user1 = insert(:user)
    user2 = insert(:user)
    email = "test@santiment.net"

    User.changeset(user1, %{email: email})
    |> Repo.update()

    {:error, changeset} =
      User.changeset(user2, %{email_candidate: email})
      |> Repo.update()

    refute changeset.valid?

    assert errors_on(changeset)[:email] |> Enum.at(0) == "Email has already been taken"
  end

  describe "#users_with_monitored_watchlist_and_email" do
    test "user has email and monitored watchlist - returns 1 record" do
      user = insert(:user)
      Sanbase.UserList.create_user_list(user, %{name: "test", is_monitored: true})
      assert length(User.users_with_monitored_watchlist_and_email()) == 1
    end

    test "user without email - returns 0 records" do
      user = insert(:user, email: nil)
      Sanbase.UserList.create_user_list(user, %{name: "test", is_monitored: true})
      assert length(User.users_with_monitored_watchlist_and_email()) == 0
    end

    test "user's watchlist is not monitored" do
      user = insert(:user)
      Sanbase.UserList.create_user_list(user, %{name: "test"})
      assert length(User.users_with_monitored_watchlist_and_email()) == 0
    end
  end

  test "user with avatar url is okay" do
    avatar_url =
      "http://stage-sanbase-images.s3.amazonaws.com/uploads/_empowr-coinHY5QG72SCGKYWMN4AEJQ2BRDLXNWXECT.png"

    {:ok, user} =
      insert(:user)
      |> Sanbase.Auth.User.update_avatar_url(avatar_url)

    assert user.avatar_url == avatar_url
  end

  test "user with invalid avatar url returns proper error" do
    avatar_url = "something invalid"

    {:error, changeset} =
      insert(:user)
      |> Sanbase.Auth.User.update_avatar_url(avatar_url)

    assert errors_on(changeset)[:avatar_url] ==
             [
               "`something invalid` is not a valid URL. Reason: it is missing scheme (e.g. missing https:// part)"
             ]
  end
end
