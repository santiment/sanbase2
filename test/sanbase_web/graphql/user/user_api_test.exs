defmodule SanbaseWeb.Graphql.UserApiTest do
  use SanbaseWeb.ConnCase, async: false

  import Mockery
  import Mock
  import SanbaseWeb.Graphql.TestHelpers
  import ExUnit.CaptureLog
  import Sanbase.Factory

  alias Sanbase.Auth.User
  alias Sanbase.Repo

  setup_with_mocks([
    {Sanbase.Billing.Subscription.SignUpTrial, [:passtrough],
     [create_subscription: fn _ -> {:ok, %{}} end]}
  ]) do
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
        id
        sanBalance
      }
    }
    """

    result =
      conn
      |> post("/graphql", query_skeleton(query, "currentUser"))
      |> json_response(200)

    assert result["data"]["currentUser"]["sanBalance"] == 0.0
  end

  test "user with san balance of 0 does not have any permissions", context do
    query = """
    {
      currentUser {
        id
        permissions{
          spreadsheet
        }
      }
    }
    """

    result =
      context.conn
      |> post("/graphql", query_skeleton(query, "currentUser"))
      |> json_response(200)

    assert result["data"]["currentUser"]["permissions"] == %{
             "spreadsheet" => false
           }
  end

  test "user with san balance of 1000 has all permisions", context do
    insert(:subscription_pro_sanbase, user: context.user)

    query = """
    {
      currentUser {
        id
        permissions{
          spreadsheet
        }
      }
    }
    """

    result =
      context.conn
      |> post("/graphql", query_skeleton(query, "currentUser"))
      |> json_response(200)

    assert result["data"]["currentUser"]["permissions"] == %{
             "spreadsheet" => true
           }
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
      emailChangeVerify(email_candidate: "#{user.email_candidate}", token: "#{user.email_candidate_token}") {
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
    assert Sanbase.TestUtils.datetime_close_to(
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

    generated_at =
      Timex.shift(NaiveDateTime.utc_now(), days: -2) |> NaiveDateTime.truncate(:second)

    user =
      user
      |> Ecto.Changeset.change(email_candidate_token_generated_at: generated_at)
      |> Repo.update!()

    query = """
    mutation {
      emailChangeVerify(email_candidate: "#{user.email_candidate}", token: "#{user.email_candidate_token}") {
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
      emailChangeVerify(email_candidate: "#{user.email_candidate}", token: "#{user.email_candidate_token}") {
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

    {:ok, user} = User.find_or_insert_by(:email, user.email)

    assert login_data["token"] != nil
    assert login_data["user"]["email"] == user.email

    assert login_data["token"] == result.private.plug_session["auth_token"]
    # Assert that now() and validated_at do not differ by more than 2 seconds
    assert Sanbase.TestUtils.datetime_close_to(
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

    generated_at = Timex.shift(Timex.now(), days: -2) |> NaiveDateTime.truncate(:second)

    user =
      user
      |> Ecto.Changeset.change(email_token_generated_at: generated_at)
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

  test "fail to login again with a valid email token after one validation", %{conn: conn} do
    {:ok, user} =
      %User{
        salt: User.generate_salt(),
        email: "example@santiment.net",
        privacy_policy_accepted: true
      }
      |> Repo.insert!()
      |> User.update_email_token()

    naive_now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    user =
      user
      |> Ecto.Changeset.change(
        email_token_generated_at: naive_now,
        email_token_validated_at: naive_now
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
      |> json_response(200)

    assert result["errors"] != nil
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

    naive_now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    user =
      user
      |> Ecto.Changeset.change(
        email_token_generated_at: naive_now,
        email_token_validated_at: Timex.shift(naive_now, minutes: -20)
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

  describe "#email_login" do
    setup_with_mocks([
      {Sanbase.MandrillApi, [], [send: fn _, _, _ -> {:ok, %{}} end]}
    ]) do
      mutation_func = fn args ->
        graphql_args_string =
          map_to_input_object_str(args)
          |> String.replace_leading("{", "")
          |> String.replace_trailing("}", "")

        """
        mutation {
          emailLogin(#{graphql_args_string}) {
            success
            firstLogin
          }
        }
        """
      end

      {:ok, mutation_func: mutation_func}
    end

    test "emailLogin returns true if the login email was sent successfully", context do
      result =
        execute_mutation(
          context.conn,
          context.mutation_func.(%{email: "john@example.com"}),
          "emailLogin"
        )

      assert Repo.get_by(User, email: "john@example.com")
      assert result["success"]
      assert result["firstLogin"]
    end

    test "emailLogin with newsletter subscription adds newsletter subscription param", context do
      result =
        execute_mutation(
          context.conn,
          context.mutation_func.(%{email: "john@example.com", subscribeToWeeklyNewsletter: true}),
          "emailLogin"
        )

      assert Repo.get_by(User, email: "john@example.com")
      assert result["success"]
      assert result["firstLogin"]

      assert_called(
        Sanbase.MandrillApi.send(
          :_,
          "john@example.com",
          :meck.is(fn %{LOGIN_LINK: login_link} ->
            assert login_link =~ "subscribe_to_weekly_newsletter=true"
          end)
        )
      )
    end
  end

  test "logout clears session", %{
    conn: conn
  } do
    query = """
    mutation {
      logout {
        success
      }
    }
    """

    result =
      conn
      |> post("/graphql", mutation_skeleton(query))

    assert json_response(result, 200)["data"]["logout"]["success"]
    assert result.private.plug_session_info == :drop
  end

  test "change avatar of current user", %{conn: conn} do
    new_avatar =
      "http://stage-sanbase-images.s3.amazonaws.com/uploads/_empowr-coinHY5QG72SCGKYWMN4AEJQ2BRDLXNWXECT.png"

    query = """
    mutation {
      changeAvatar(avatar_url: "#{new_avatar}") {
        avatarUrl
      }
    }
    """

    result =
      conn
      |> post("/graphql", mutation_skeleton(query))

    assert json_response(result, 200)["data"]["changeAvatar"]["avatarUrl"] == new_avatar
  end

  test "invalid avatar url returns proper error message", %{conn: conn} do
    invalid_avatar = "something invalid"

    query = """
    mutation {
      changeAvatar(avatar_url: "#{invalid_avatar}") {
        avatarUrl
      }
    }
    """

    result =
      conn
      |> post("/graphql", mutation_skeleton(query))

    %{
      "data" => %{"changeAvatar" => nil},
      "errors" => [
        %{
          "message" => message,
          "details" => details
        }
      ]
    } = json_response(result, 200)

    assert message == "Cannot change the avatar"

    assert details ==
             %{
               "avatar_url" => [
                 "`something invalid` is not a valid URL. Reason: it is missing scheme (e.g. missing https:// part)"
               ]
             }
  end
end
