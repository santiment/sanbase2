defmodule SanbaseWeb.Graphql.UserApiTest do
  use SanbaseWeb.ConnCase, async: false

  import Mock
  import Mox
  import SanbaseWeb.Graphql.TestHelpers
  import ExUnit.CaptureLog
  import Sanbase.Factory

  alias Sanbase.Accounts.User
  alias Sanbase.Repo

  setup :set_mox_from_context
  setup :verify_on_exit!

  setup_with_mocks([
    {Sanbase.TemplateMailer, [], [send: fn _, _, _ -> {:ok, :email_sent} end]}
  ]) do
    user = insert(:user)

    conn = setup_jwt_auth(build_conn(), user)

    {:ok, conn: conn, user: user}
  end

  describe "firstLogin" do
    test "firstLogin when state is waiting for login to finish registration" do
      expect(Sanbase.Email.MockMailjetApi, :subscribe, fn _, _ -> :ok end)
      user = insert(:user_registration_not_finished)
      conn = setup_jwt_auth(build_conn(), user)

      # Check that after the state is in `waiting_for_login_to_finish`, which is
      # achieved by google/twitter oauth actions, the registration process is
      # finished when the `firstLogin` field is queried. This is so the frontend
      # does not need to introduce any locks and waits to make sure the request
      # that checks for firstLogin executes first and before any other currentUser
      # request.
      {:ok, :evolve_state, _user} =
        Sanbase.Accounts.forward_registration(user, "google_oauth", %{
          login_origin: :google,
          origin_url: "localhost"
        })

      user_id =
        conn
        |> post("/graphql", query_skeleton("{ currentUser{ id } }"))
        |> json_response(200)
        |> get_in(["data", "currentUser", "id"])

      assert user.id == String.to_integer(user_id)

      # firstLogin is set to true and the registration is finished only
      # when `firstLogin` field is requested for the first time.

      first_login =
        conn
        |> post("/graphql", query_skeleton("{ currentUser{ firstLogin } }"))
        |> json_response(200)
        |> get_in(["data", "currentUser", "firstLogin"])

      assert first_login == true

      first_login =
        conn
        |> post("/graphql", query_skeleton("{ currentUser{ firstLogin } }"))
        |> json_response(200)
        |> get_in(["data", "currentUser", "firstLogin"])

      assert first_login == false
    end
  end

  describe "Current user" do
    test "default san_balance is 0.0", %{conn: conn} do
      query = """
      {
        currentUser {
          id
          sanBalance
        }
      }
      """

      assert execute_query(conn, query, "currentUser")["sanBalance"] == +0.0
    end

    test "with Sanbase Pro subscription has spreadsheets permissions", context do
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

      result = execute_query(context.conn, query, "currentUser")
      assert result["permissions"] == %{"spreadsheet" => true}
    end
  end

  describe "Change email" do
    test "with non-existing, creates new email candidate", %{conn: conn, user: user} do
      new_email = "new_test_email@santiment.net"

      mutation = """
      mutation {
        changeEmail(email: "#{new_email}") {
          success
        }
      }
      """

      result = execute_mutation(conn, mutation, "changeEmail")
      assert_called(Sanbase.TemplateMailer.send(new_email, :_, :_))
      assert result["success"] == true
      assert Repo.get(User, user.id).email_candidate == new_email
    end

    test "when such email exists, gives meaningful error", %{conn: conn} do
      new_email = "new_test_email@santiment.net"
      insert(:user, email: new_email)

      mutation = """
      mutation {
        changeEmail(email: "#{new_email}") {
          success
        }
      }
      """

      capture_log(fn ->
        error_msg = execute_mutation_with_error(conn, mutation)
        assert error_msg =~ "Can't change current user's email to new_test_email@santiment.net"
      end)
    end
  end

  describe "Verify change of email" do
    test "trying to verify email candidate using invalid token for a user", %{conn: conn} do
      user = insert(:user, email_candidate: "example@santiment.net")

      mutation = """
      mutation {
        emailChangeVerify(email_candidate: "#{user.email}", token: "invalid_token") {
          user {
            email
          },
          token
        }
      }
      """

      error_msg = execute_mutation_with_error(conn, mutation)
      assert error_msg == "Email change verify failed"
    end

    test "trying to verify email_candidate with a valid email_candidate_token", %{conn: conn} do
      {:ok, user} =
        insert(:user, email: "example@santiment.net")
        |> User.Email.update_email_candidate("example+foo@santiment.net")

      mutation = """
      mutation {
        emailChangeVerify(email_candidate: "#{user.email_candidate}", token: "#{user.email_candidate_token}") {
          user {
            email
          }
          accessToken
        }
      }
      """

      result = execute_mutation(conn, mutation, "emailChangeVerify")
      user = Repo.get_by(User, email: user.email_candidate)

      assert result["accessToken"] != nil
      assert result["user"]["email"] == user.email
      assert user.email_candidate == nil
      # Assert that now() and validated_at do not differ by more than 2 seconds
      assert Sanbase.TestUtils.datetime_close_to(
               Timex.now(),
               user.email_candidate_token_validated_at,
               2,
               :seconds
             )
    end

    test "trying to verify email_candidate with a valid token after more than 1 day", %{
      conn: conn
    } do
      {:ok, user} =
        insert(:user, email: "example@santiment.net")
        |> User.Email.update_email_candidate("example+foo@santiment.net")

      generated_at =
        Timex.shift(NaiveDateTime.utc_now(), days: -2) |> NaiveDateTime.truncate(:second)

      user =
        user
        |> Ecto.Changeset.change(email_candidate_token_generated_at: generated_at)
        |> Repo.update!()

      mutation = """
      mutation {
        emailChangeVerify(email_candidate: "#{user.email_candidate}", token: "#{user.email_candidate_token}") {
          user {
            email
          }
          token
        }
      }
      """

      error_msg = execute_mutation_with_error(conn, mutation)
      assert error_msg == "Email change verify failed"
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
        |> User.Email.update_email_candidate("example+foo@santiment.net")

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

      assert message == "Email change verify failed"
    end
  end

  test "Change name of current user", %{conn: conn} do
    # allow non-ascii symbols as well
    new_name = "new име utf8 José"

    mutation = """
    mutation {
      changeName(name: "#{new_name}") {
        name
      }
    }
    """

    result = execute_mutation(conn, mutation, "changeName")
    assert result["name"] == new_name
  end

  test "Change username of current user", %{conn: conn} do
    new_username = "new_username_changed"

    mutation = """
    mutation {
      changeUsername(username: "#{new_username}") {
        username
      }
    }
    """

    result = execute_mutation(conn, mutation, "changeUsername")
    assert result["username"] == new_username
  end

  test "logout clears session", %{conn: conn} do
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

  describe "Change avatar" do
    test "change avatar of current user", %{conn: conn} do
      new_avatar =
        "http://stage-sanbase-images.s3.amazonaws.com/uploads/_empowr-coinHY5QG72SCGKYWMN4AEJQ2BRDLXNWXECT.png"

      mutation = """
      mutation {
        changeAvatar(avatar_url: "#{new_avatar}") {
          avatarUrl
        }
      }
      """

      assert execute_mutation(conn, mutation, "changeAvatar")["avatarUrl"] == new_avatar
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
                   "URL 'something invalid' is missing a scheme (e.g. https)"
                 ]
               }
    end
  end

  test "check is moderator", %{conn: conn, user: user} do
    query = "{ currentUser{ isModerator } }"

    assert false ==
             conn
             |> post("/graphql", query_skeleton(query))
             |> json_response(200)
             |> get_in(["data", "currentUser", "isModerator"])

    role = insert(:role_san_moderator)
    assert {:ok, _} = Sanbase.Accounts.UserRole.create(user.id, role.id)

    # Clear the cache that hols the moderator user ids
    Sanbase.Cache.clear_all()

    assert true ==
             conn
             |> post("/graphql", query_skeleton(query))
             |> json_response(200)
             |> get_in(["data", "currentUser", "isModerator"])
  end

  describe "Update user profile" do
    test "successfully updates profile fields", %{conn: conn} do
      mutation = """
      mutation {
        updateUserProfile(
          description: "Test description"
          websiteUrl: "https://example.com"
          twitterHandle: "test"
        ) {
          description
          websiteUrl
          twitterHandle
        }
      }
      """

      result = execute_mutation(conn, mutation, "updateUserProfile")

      assert result["description"] == "Test description"
      assert result["websiteUrl"] == "https://example.com"
      assert result["twitterHandle"] == "test"
    end

    test "can update individual fields", %{conn: conn} do
      mutation = """
      mutation {
        updateUserProfile(description: "Only description updated") {
          description
          websiteUrl
          twitterHandle
        }
      }
      """

      result = execute_mutation(conn, mutation, "updateUserProfile")

      assert result["description"] == "Only description updated"
      assert result["websiteUrl"] == nil
      assert result["twitterHandle"] == nil
    end

    test "invalid URL format returns error", %{conn: conn} do
      mutation = """
      mutation {
        updateUserProfile(websiteUrl: "invalid-url") {
          websiteUrl
        }
      }
      """

      result =
        conn
        |> post("/graphql", mutation_skeleton(mutation))

      error = json_response(result, 200)["errors"] |> hd()

      assert error["details"] == %{
               "website_url" => ["URL 'invalid-url' is missing a scheme (e.g. https)"]
             }

      assert error["message"] == "Cannot update user profile"
    end
  end
end
