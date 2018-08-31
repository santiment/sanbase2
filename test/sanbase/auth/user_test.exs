defmodule Sanbase.Auth.UserTest do
  use Sanbase.DataCase, async: false

  import Mockery
  import Sanbase.Factory

  alias Sanbase.Auth.{User, EthAccount}
  alias Sanbase.Repo

  test "san balance cache is stale when the cache is never updated" do
    user = insert(:user, privacy_policy_accepted: true)

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
    mock(Sanbase.InternalServices.Ethauth, :san_balance, {:ok, Decimal.new(5)})

    user =
      insert(:user,
        san_balance: 0,
        eth_accounts: [%EthAccount{address: "0x000000000001"}],
        privacy_policy_accepted: true
      )

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
    user =
      insert(:user,
        san_balance_updated_at: Timex.now(),
        san_balance: Decimal.new(5),
        privacy_policy_accepted: true
      )

    assert User.san_balance!(user) == Decimal.new(5)
  end

  test "san_balance! updates the balance if the balance cache is stale" do
    user =
      insert(:user,
        san_balance_updated_at: Timex.shift(Timex.now(), minutes: -10),
        privacy_policy_accepted: true
      )

    mock(Sanbase.InternalServices.Ethauth, :san_balance, {:ok, Decimal.new(10)})

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
      insert(:user,
        san_balance: Decimal.new(10),
        test_san_balance: Decimal.new(20),
        san_balance_updated_at: Timex.shift(Timex.now(), minutes: -2)
      )

    assert User.san_balance!(user) == Decimal.new(20)
  end

  test "san_balance! returns cached san_balance if test_san_balance not present" do
    user =
      insert(:user,
        san_balance: Decimal.new(10),
        san_balance_updated_at: Timex.shift(Timex.now(), minutes: -2),
        privacy_policy_accepted: true
      )

    assert User.san_balance!(user) == Decimal.new(10)
  end

  test "find_or_insert_by_email when the user does not exist" do
    {:ok, user} = User.find_or_insert_by_email("test@example.com", "john_snow")

    assert user.email == "test@example.com"
    assert user.username == "john_snow"
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

    assert Sanbase.TestUtils.date_close_to(
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

    assert Sanbase.TestUtils.date_close_to(
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

    assert Sanbase.TestUtils.date_close_to(
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

    assert Sanbase.TestUtils.date_close_to(
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

  test "find_or_insert_by_email when the user does not exist" do
    {:ok, user} = User.find_or_insert_by_email("test@example.com", "john_snow")

    assert user.email == "test@example.com"
    assert user.username == "john_snow"
  end

  test "find_or_insert_by_email when the user exists" do
    existing_user =
      %User{email: "test@example.com", username: "cersei", salt: User.generate_salt()}
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

  test "return error on insert/update username with non ascii" do
    user = insert(:user)

    {:error, changeset} =
    User.changeset(user, %{username: "周必聪"})
    |> Repo.update()

    refute changeset.valid?
    assert errors_on(changeset)[:username] |> Enum.at(0) == "Username contains non ascii characters"
  end

  test "trim whitespace on username" do
    user = insert(:user)

    {:ok, user} = User.changeset(user, %{username: " portokala "})
    |> Repo.update()

    assert user.username == "portokala"
  end
end
