defmodule SanbaseWeb.Graphql.EmailLoginApiTest do
  use SanbaseWeb.ConnCase

  import Mock
  import SanbaseWeb.Graphql.TestHelpers
  import Sanbase.Factory

  alias Sanbase.Accounts.User
  alias Sanbase.Repo

  setup do
    user = insert(:user)

    conn = setup_jwt_auth(build_conn(), user)

    {:ok, conn: conn, user: user}
  end

  describe "Email login verify" do
    test "with a valid email token, succeeds login", %{conn: conn} do
      {:ok, user} =
        insert(:user, email: "example@santiment.net")
        |> User.update_email_token()

      mutation = email_login_verify_mutation(user)

      result =
        conn
        |> post("/graphql", mutation_skeleton(mutation))

      login_data = result |> json_response(200) |> get_in(["data", "emailLoginVerify"])
      {:ok, user} = User.by_email(user.email)

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

    test "with a valid email token, succeeds login after more than 5 minutes" do
      {:ok, user} =
        insert(:user, email: "example@santiment.net")
        |> User.update_email_token()

      mutation = email_login_verify_mutation(user)

      conn =
        build_conn()
        |> post("/graphql", mutation_skeleton(mutation))

      new_now = DateTime.utc_now() |> DateTime.to_unix() |> Kernel.+(3600)

      # Guardian uses System.system_time(:second) in the expiry checks
      Sanbase.Mock.prepare_mock2(&System.system_time/1, new_now)
      |> Sanbase.Mock.run_with_mocks(fn ->
        new_conn =
          conn
          |> post("/graphql", query_skeleton("{ currentUser{ id } }"))

        # Still logged in
        assert json_response(new_conn, 200)["data"]["currentUser"]["id"] == to_string(user.id)

        old_session = Plug.Conn.get_session(conn)
        new_session = Plug.Conn.get_session(new_conn)

        # Asser that the access token has been silently updated as 1 hour has
        # passed since it was issued
        assert old_session["refresh_token"] == new_session["refresh_token"]
        assert old_session["access_token"] != new_session["access_token"]
      end)
    end

    test "with invalid token for a user, fail to login", %{conn: conn} do
      user = insert(:user, email: "example@santiment.net")

      mutation = """
      mutation {
        emailLoginVerify(email: "#{user.email}", token: "invalid_token") {
          user {
            email
          },
          token
        }
      }
      """

      error_msg = execute_mutation_with_error(conn, mutation)
      assert error_msg != ""
    end

    test "with a valid email token after more than 1 day, fail to login", %{conn: conn} do
      {:ok, user} =
        insert(:user, email: "example@santiment.net")
        |> User.update_email_token()

      generated_at = Timex.shift(Timex.now(), days: -2) |> NaiveDateTime.truncate(:second)

      user =
        user
        |> Ecto.Changeset.change(email_token_generated_at: generated_at)
        |> Repo.update!()

      mutation = email_login_verify_mutation(user)

      error_msg = execute_mutation_with_error(conn, mutation)
      assert error_msg == "Login failed"
    end

    test "with a valid email token after one validation, fail to login again", %{conn: conn} do
      {:ok, user} =
        insert(:user, email: "example@santiment.net")
        |> User.update_email_token()

      naive_now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

      user =
        user
        |> Ecto.Changeset.change(
          email_token_generated_at: naive_now,
          email_token_validated_at: naive_now
        )
        |> Repo.update!()

      mutation = email_login_verify_mutation(user)
      error_msg = execute_mutation_with_error(conn, mutation)

      assert error_msg == "Login failed"
    end

    test "with a valid email token after it has been validated 20 min ago, fail to login",
         %{conn: conn} do
      {:ok, user} =
        insert(:user, email: "example@santiment.net")
        |> User.update_email_token()

      naive_now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

      user =
        user
        |> Ecto.Changeset.change(
          email_token_generated_at: naive_now,
          email_token_validated_at: Timex.shift(naive_now, minutes: -20)
        )
        |> Repo.update!()

      mutation = email_login_verify_mutation(user)
      error_msg = execute_mutation_with_error(conn, mutation)

      assert error_msg == "Login failed"
    end
  end

  describe "Email login" do
    setup_with_mocks([
      {Sanbase.TemplateMailer, [], [send: fn _, _, _ -> {:ok, %{}} end]}
    ]) do
      []
    end

    defp email_login(conn, args) do
      mutation = """
      mutation {
        emailLogin(#{map_to_args(args)}) {
          success
          firstLogin
        }
      }
      """

      conn
      |> post("/graphql", mutation_skeleton(mutation))
      |> json_response(200)
    end

    test "emailLogin fails when origin is not santiment", context do
      error_msg =
        context.conn
        |> Plug.Conn.put_req_header("origin", "https://app.santiemnt.net")
        |> email_login(%{email: "john@example.com"})
        |> get_in(["errors", Access.at(0), "message"])

      assert error_msg == "Can't login"
    end

    test "emailLogin returns true with santiment.net origin", context do
      result =
        context.conn
        |> Plug.Conn.put_req_header("origin", "https://santiment.net")
        |> email_login(%{email: "john@example.com"})
        |> get_in(["data", "emailLogin"])

      assert {:ok, %User{}} = User.by_email("john@example.com")
      assert result["success"]
      assert result["firstLogin"]
    end

    test "emailLogin returns true if the login email was sent successfully", context do
      result =
        context.conn
        |> Plug.Conn.put_req_header("origin", "https://app.santiment.net")
        |> email_login(%{email: "john@example.com"})
        |> get_in(["data", "emailLogin"])

      assert {:ok, %User{}} = User.by_email("john@example.com")
      assert result["success"]
      assert result["firstLogin"]
    end

    test "succeeds if the user has attempted to login 5 times", context do
      user = insert(:user, email: "john@example.com")

      for _ <- 1..5,
          do: insert(:email_login_attempt, user: user, ip_address: "127.0.0.1")

      result =
        context.conn
        |> Plug.Conn.put_req_header("origin", "https://app.santiment.net")
        |> email_login(%{email: "john@example.com"})
        |> get_in(["data", "emailLogin"])

      assert result["success"]
    end

    test "succeeds when different users login from the same ip not more than 20 times", context do
      user1 = insert(:user, email: "john@example.com")
      user2 = insert(:user, email: "jane@example.com")
      user3 = insert(:user, email: "jake@example.com")
      user4 = insert(:user, email: "joel@example.com")

      for _ <- 1..5,
          do: insert(:email_login_attempt, user: user1, ip_address: "127.0.0.1")

      for _ <- 1..5,
          do: insert(:email_login_attempt, user: user2, ip_address: "127.0.0.1")

      for _ <- 1..5,
          do: insert(:email_login_attempt, user: user3, ip_address: "127.0.0.1")

      for _ <- 1..5,
          do: insert(:email_login_attempt, user: user4, ip_address: "127.0.0.1")

      result =
        context.conn
        |> Plug.Conn.put_req_header("origin", "https://app.santiment.net")
        |> email_login(%{email: "john@example.com"})
        |> get_in(["data", "emailLogin"])

      assert result["success"]
    end

    test "fails if the user has attempted to login more than 5 times having the same email",
         context do
      user = insert(:user, email: "john@example.com")

      for _ <- 1..6,
          # As the login attemt in this test is made on localhost, the below ip should not match
          do: insert(:email_login_attempt, user: user, ip_address: "157.7.7.7")

      msg =
        context.conn
        |> Plug.Conn.put_req_header("origin", "https://app.santiment.net")
        |> email_login(%{email: "john@example.com"})
        |> Map.get("errors")
        |> hd()
        |> Map.get("message")

      assert msg =~ "Too many login attempts"
    end

    test "fails if the user has attempted to login more than 20 having the same ip",
         context do
      user1 = insert(:user, email: "john@example.com")
      user2 = insert(:user, email: "jane@example.com")

      for _ <- 1..11,
          do: insert(:email_login_attempt, user: user1, ip_address: "127.0.0.1")

      for _ <- 1..11,
          do: insert(:email_login_attempt, user: user2, ip_address: "127.0.0.1")

      msg =
        context.conn
        |> Plug.Conn.put_req_header("origin", "https://app.santiment.net")
        |> email_login(%{email: "john@example.com"})
        |> Map.get("errors")
        |> hd()
        |> Map.get("message")

      assert msg =~ "Too many login attempts"
    end
  end

  defp email_login_verify_mutation(user) do
    """
    mutation {
      emailLoginVerify(email: "#{user.email}", token: "#{user.email_token}") {
        user {
          email
          settings {
            newsletterSubscription
          }
        }
        token

      }
    }
    """
  end
end
