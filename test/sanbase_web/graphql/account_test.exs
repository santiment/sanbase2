defmodule SanbaseWeb.Graphql.AccountTest do
  use SanbaseWeb.ConnCase, async: false

  alias Sanbase.Auth.User
  alias Sanbase.Repo

  import Mockery
  import SanbaseWeb.Graphql.TestHelpers
  import ExUnit.CaptureLog

  setup do
    user =
      %User{salt: User.generate_salt(), privacy_policy_accepted: true}
      |> Repo.insert!()

    conn = setup_jwt_auth(build_conn(), user)

    {:ok, conn: conn, user: user}
  end

  test "the default current user's san_balance is 0.0", %{conn: conn} do
    query = """
    {
      currentUser {
        id,
        sanBalance
      }
    }
    """

    result =
      conn
      |> post("/graphql", query_skeleton(query, "currentUser"))

    assert json_response(result, 200)["data"]["currentUser"]["sanBalance"] == 0.0
  end

  test "change email of current user", %{conn: conn, user: user} do
    mock(Sanbase.MandrillApi, :send, {:ok, %{}})

    new_email = "new_test_email@santiment.net"

    query = """
    mutation {
      changeEmail(email: "#{new_email}") {
        success
      }
    }
    """

    result =
      conn
      |> post("/graphql", mutation_skeleton(query))

    assert json_response(result, 200)["data"]["changeEmail"]["success"] == true
    assert Repo.get(User, user.id).email_candidate == new_email
  end

  test "change email to an existing one gives meaningful error", %{conn: conn} do
    new_email = "new_test_email@santiment.net"

    %User{
      salt: User.generate_salt(),
      email: new_email
    }
    |> Repo.insert!()

    query = """
    mutation {
      changeEmail(email: "#{new_email}") {
        success
      }
    }
    """

    capture_log(fn ->
      result =
        conn
        |> post("/graphql", mutation_skeleton(query))
        |> json_response(200)

      %{
        "data" => %{"changeEmail" => nil},
        "errors" => [
          %{
            "details" => details
          }
        ]
      } = result

      assert details == %{"email" => ["Email has already been taken"]}
    end)
  end

  test "trying to verify email candidate using invalid token for a user", %{conn: conn} do
    user =
      %User{
        salt: User.generate_salt(),
        email_candidate: "example@santiment.net",
        privacy_policy_accepted: true
      }
      |> Repo.insert!()

    query = """
    mutation {
      emailChangeVerify(email_candidate: "#{user.email}", token: "invalid_token") {
        user {
          email
        },
        token
      }
    }
    """

    result =
      conn
      |> post("/graphql", mutation_skeleton(query))
      |> json_response(200)

    %{
      "data" => %{"emailChangeVerify" => nil},
      "errors" => [
        %{
          "message" => message
        }
      ]
    } = result

    assert message == "Login failed"
  end

  test "trying to verify email_candidate with a valid email_candidate_token", %{conn: conn} do
    {:ok, user} =
      %User{
        salt: User.generate_salt(),
        email: "example@santiment.net",
        privacy_policy_accepted: true
      }
      |> Repo.insert!()
      |> User.update_email_candidate("example+foo@santiment.net")

    query = """
    mutation {
      emailChangeVerify(email_candidate: "#{user.email_candidate}", token: "#{
      user.email_candidate_token
    }") {
        user {
          email
        },
        token
      }
    }
    """

    result =
      conn
      |> post("/graphql", mutation_skeleton(query))
      |> json_response(200)

    login_data = result["data"]["emailChangeVerify"]

    user = Repo.get_by(User, email: user.email_candidate)

    assert login_data["token"] != nil
    assert login_data["user"]["email"] == user.email
    assert user.email_candidate == nil

    # Assert that now() and validated_at do not differ by more than 2 seconds
    assert Sanbase.TestUtils.date_close_to(
             Timex.now(),
             user.email_candidate_token_validated_at,
             2,
             :seconds
           )
  end

  test "trying to verify email_candidate with a valid token after more than 1 day", %{conn: conn} do
    {:ok, user} =
      %User{
        salt: User.generate_salt(),
        email: "example@santiment.net",
        privacy_policy_accepted: true
      }
      |> Repo.insert!()
      |> User.update_email_candidate("example+foo@santiment.net")

    user =
      user
      |> Ecto.Changeset.change(
        email_candidate_token_generated_at: Timex.shift(Timex.now(), days: -2)
      )
      |> Repo.update!()

    query = """
    mutation {
      emailChangeVerify(email_candidate: "#{user.email_candidate}", token: "#{
      user.email_candidate_token
    }") {
        user {
          email
        }
        token
      }
    }
    """

    result =
      conn
      |> post("/graphql", mutation_skeleton(query))
      |> json_response(200)

    %{
      "data" => %{"emailChangeVerify" => nil},
      "errors" => [
        %{
          "message" => message
        }
      ]
    } = result

    assert message == "Login failed"
  end

  test "trying to verify email_candidate again with a valid token after one validation", %{
    conn: conn
  } do
    {:ok, user} =
      %User{
        salt: User.generate_salt(),
        email: "example@santiment.net",
        privacy_policy_accepted: true
      }
      |> Repo.insert!()
      |> User.update_email_candidate("example+foo@santiment.net")

    query = """
    mutation {
      emailChangeVerify(email_candidate: "#{user.email_candidate}", token: "#{
      user.email_candidate_token
    }") {
        user {
          email
        }
        token
      }
    }
    """

    post(conn, "/graphql", mutation_skeleton(query))

    result =
      conn
      |> post("/graphql", mutation_skeleton(query))
      |> json_response(200)

    %{
      "data" => %{"emailChangeVerify" => nil},
      "errors" => [
        %{
          "message" => message
        }
      ]
    } = result

    assert message == "Login failed"
  end

  test "change username of current user", %{conn: conn} do
    new_username = "new_username_changed"

    query = """
    mutation {
      changeUsername(username: "#{new_username}") {
        username
      }
    }
    """

    result =
      conn
      |> post("/graphql", mutation_skeleton(query))

    assert json_response(result, 200)["data"]["changeUsername"]["username"] == new_username
  end

  test "trying to login using invalid token for a user", %{conn: conn} do
    user =
      %User{
        salt: User.generate_salt(),
        email: "example@santiment.net",
        privacy_policy_accepted: true
      }
      |> Repo.insert!()

    query = """
    mutation {
      emailLoginVerify(email: "#{user.email}", token: "invalid_token") {
        user {
          email
        },
        token
      }
    }
    """

    result =
      conn
      |> post("/graphql", mutation_skeleton(query))

    assert json_response(result, 200)["errors"] != nil
  end

  test "trying to login with a valid email token", %{conn: conn} do
    {:ok, user} =
      %User{
        salt: User.generate_salt(),
        email: "example@santiment.net",
        privacy_policy_accepted: true
      }
      |> Repo.insert!()
      |> User.update_email_token()

    query = """
    mutation {
      emailLoginVerify(email: "#{user.email}", token: "#{user.email_token}") {
        user {
          email
        },
        token
      }
    }
    """

    result =
      conn
      |> post("/graphql", mutation_skeleton(query))

    login_data = json_response(result, 200)["data"]["emailLoginVerify"]

    {:ok, user} = User.find_or_insert_by_email(user.email)

    assert login_data["token"] != nil
    assert login_data["user"]["email"] == user.email

    # Assert that now() and validated_at do not differ by more than 2 seconds
    assert Sanbase.TestUtils.date_close_to(
             Timex.now(),
             user.email_token_validated_at,
             2,
             :seconds
           )
  end

  test "trying to login with a valid email token after more than 1 day", %{conn: conn} do
    {:ok, user} =
      %User{
        salt: User.generate_salt(),
        email: "example@santiment.net",
        privacy_policy_accepted: true
      }
      |> Repo.insert!()
      |> User.update_email_token()

    user =
      user
      |> Ecto.Changeset.change(email_token_generated_at: Timex.shift(Timex.now(), days: -2))
      |> Repo.update!()

    query = """
    mutation {
      emailLoginVerify(email: "#{user.email}", token: "#{user.email_token}") {
        user {
          email
        }
        token
      }
    }
    """

    result =
      conn
      |> post("/graphql", mutation_skeleton(query))

    assert json_response(result, 200)["errors"] != nil
  end

  test "trying to login again with a valid email token after one validation", %{conn: conn} do
    {:ok, user} =
      %User{
        salt: User.generate_salt(),
        email: "example@santiment.net",
        privacy_policy_accepted: true
      }
      |> Repo.insert!()
      |> User.update_email_token()

    user =
      user
      |> Ecto.Changeset.change(
        email_token_generated_at: Timex.now(),
        email_token_validated_at: Timex.now()
      )
      |> Repo.update!()

    query = """
    mutation {
      emailLoginVerify(email: "#{user.email}", token: "#{user.email_token}") {
        user {
          email
        }
        token
      }
    }
    """

    result =
      conn
      |> post("/graphql", mutation_skeleton(query))

    login_data = json_response(result, 200)["data"]["emailLoginVerify"]

    assert login_data["token"] != nil
    assert login_data["user"]["email"] == user.email
  end

  test "trying to login again with a valid email token after it has been validated 20 min ago", %{
    conn: conn
  } do
    {:ok, user} =
      %User{
        salt: User.generate_salt(),
        email: "example@santiment.net",
        privacy_policy_accepted: true
      }
      |> Repo.insert!()
      |> User.update_email_token()

    user =
      user
      |> Ecto.Changeset.change(
        email_token_generated_at: Timex.now(),
        email_token_validated_at: Timex.shift(Timex.now(), minutes: -20)
      )
      |> Repo.update!()

    query = """
    mutation {
      emailLoginVerify(email: "#{user.email}", token: "#{user.email_token}") {
        user {
          email
        }
        token
      }
    }
    """

    result =
      conn
      |> post("/graphql", mutation_skeleton(query))

    assert json_response(result, 200)["errors"] != nil
  end

  test "emailLogin returns true if the login email was sent successfully", %{
    conn: conn
  } do
    mock(Sanbase.MandrillApi, :send, {:ok, %{}})

    query = """
    mutation {
      emailLogin(email: "john@example.com") {
        success
      }
    }
    """

    result =
      conn
      |> post("/graphql", mutation_skeleton(query))

    assert Repo.get_by(User, email: "john@example.com")
    assert json_response(result, 200)["data"]["emailLogin"]["success"]
  end
end
