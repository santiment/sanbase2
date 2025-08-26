defmodule SanbaseWeb.Graphql.EmailLoginApiTest do
  use SanbaseWeb.ConnCase

  import Mock
  import Mox
  import SanbaseWeb.Graphql.TestHelpers
  import Sanbase.Factory
  import Ecto.Query

  alias Sanbase.Accounts.User
  alias Sanbase.Repo

  setup :set_mox_from_context
  setup :verify_on_exit!

  setup do
    user = insert(:user)

    conn = setup_jwt_auth(build_conn(), user)

    {:ok, conn: conn, user: user}
  end

  describe "Email login verify" do
    test "with a valid email token, succeeds login", %{conn: conn} do
      expect(Sanbase.Email.MockMailjetApi, :subscribe, fn _, _ -> :ok end)

      {:ok, user} =
        insert(:user_registration_not_finished, email: "example@santiment.net")
        |> User.Email.update_email_token()

      result =
        conn
        |> post("/graphql", mutation_skeleton(email_login_verify_mutation(user)))

      login_data = result |> json_response(200) |> get_in(["data", "emailLoginVerify"])
      {:ok, user} = User.by_email(user.email)

      assert login_data["accessToken"] != nil
      assert login_data["user"]["firstLogin"] == true
      assert login_data["user"]["email"] == user.email

      assert login_data["accessToken"] == result.private.plug_session["access_token"]

      # Assert that now() and validated_at do not differ by more than 2 seconds
      assert Sanbase.TestUtils.datetime_close_to(
               Timex.now(),
               user.email_token_validated_at,
               2,
               :seconds
             )

      # Second login has firstLogin == false
      {:ok, user} = user |> User.Email.update_email_token()

      login_data =
        conn
        |> post("/graphql", mutation_skeleton(email_login_verify_mutation(user)))
        |> json_response(200)
        |> get_in(["data", "emailLoginVerify"])

      assert login_data["user"]["firstLogin"] == false
    end

    test "with a valid email token, succeeds login after more than 5 minutes" do
      {:ok, user} =
        insert(:user, email: "example@santiment.net")
        |> User.Email.update_email_token()

      mutation = email_login_verify_mutation(user)

      conn =
        build_conn()
        |> post("/graphql", mutation_skeleton(mutation))

      new_now = DateTime.utc_now() |> DateTime.to_unix() |> Kernel.+(3600)

      Sanbase.Mock.prepare_mock2(&Guardian.timestamp/0, new_now)
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
        |> User.Email.update_email_token()

      generated_at = Timex.shift(Timex.now(), days: -2) |> NaiveDateTime.truncate(:second)

      user =
        user
        |> Ecto.Changeset.change(email_token_generated_at: generated_at)
        |> Repo.update!()

      mutation = email_login_verify_mutation(user)

      error_msg = execute_mutation_with_error(conn, mutation)
      assert error_msg == "Email Login verification failed"
    end

    test "with a valid email token after one validation more than 5 minutes ago, fail to login again",
         %{conn: conn} do
      {:ok, user} =
        insert(:user, email: "example@santiment.net")
        |> User.Email.update_email_token()

      naive_now = NaiveDateTime.utc_now()

      user =
        user
        |> Ecto.Changeset.change(
          email_token_generated_at:
            Timex.shift(naive_now, minutes: -10) |> NaiveDateTime.truncate(:second),
          email_token_validated_at:
            Timex.shift(naive_now, minutes: -6) |> NaiveDateTime.truncate(:second)
        )
        |> Repo.update!()

      mutation = email_login_verify_mutation(user)
      error_msg = execute_mutation_with_error(conn, mutation)

      assert error_msg == "Email Login verification failed"
    end

    test "with a valid email token after one validation less than 5 minutes ago, succeeds to login again",
         %{conn: conn} do
      {:ok, user} =
        insert(:user, email: "example@santiment.net")
        |> User.Email.update_email_token()

      naive_now = NaiveDateTime.utc_now()

      user =
        user
        |> Ecto.Changeset.change(
          email_token_generated_at:
            Timex.shift(naive_now, minutes: -10) |> NaiveDateTime.truncate(:second),
          email_token_validated_at:
            Timex.shift(naive_now, minutes: -2) |> NaiveDateTime.truncate(:second)
        )
        |> Repo.update!()

      mutation = email_login_verify_mutation(user)
      result = execute_mutation(conn, mutation)

      assert %{"accessToken" => _, "user" => _} = result
    end

    test "with a valid email token after it has been validated 20 min ago, fail to login",
         %{conn: conn} do
      {:ok, user} =
        insert(:user, email: "example@santiment.net")
        |> User.Email.update_email_token()

      naive_now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
      naive_20m_ago = Timex.shift(naive_now, minutes: -20) |> NaiveDateTime.truncate(:second)

      user =
        user
        |> Ecto.Changeset.change(
          email_token_generated_at: naive_now,
          email_token_validated_at: naive_20m_ago
        )
        |> Repo.update!()

      mutation = email_login_verify_mutation(user)
      error_msg = execute_mutation_with_error(conn, mutation)

      assert error_msg == "Email Login verification failed"
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

    @tag capture_log: true
    test "emailLogin fails when origin is not santiment", context do
      error_msg =
        context.conn
        |> Plug.Conn.put_req_header("origin", "https://app.not-santiment.net")
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
    end

    test "emailLogin returns true if the login email was sent successfully", context do
      result =
        context.conn
        |> Plug.Conn.put_req_header("origin", "https://app.santiment.net")
        |> email_login(%{email: "john@example.com"})
        |> get_in(["data", "emailLogin"])

      assert {:ok, %User{}} = User.by_email("john@example.com")
      assert result["success"]
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

    test "emailLogin adds success_redirect_url and fail_redirect_url to sent login link",
         context do
      result =
        context.conn
        |> Plug.Conn.put_req_header("origin", "https://santiment.net")
        |> email_login(%{
          email: "john@example.com",
          success_redirect_url: "https://app.santiment.net/success",
          fail_redirect_url: "https://app.santiment.net/fail"
        })
        |> get_in(["data", "emailLogin"])

      assert {:ok, %User{}} = User.by_email("john@example.com")
      assert result["success"]

      [{_pid, {Sanbase.TemplateMailer, :send, [_, _, %{login_link: login_link}]}, _}] =
        call_history(Sanbase.TemplateMailer)

      url = URI.parse(login_link)
      params = URI.decode_query(url.query)

      assert params["success_redirect_url"] == "https://app.santiment.net/success"
      assert params["fail_redirect_url"] == "https://app.santiment.net/fail"
    end

    @tag capture_log: true
    test "emailLogin return error if one of redirect urls is not from domain santiment.net",
         context do
      msg =
        context.conn
        |> Plug.Conn.put_req_header("origin", "https://santiment.net")
        |> email_login(%{
          email: "john@example.com",
          success_redirect_url: "https://example.com/success",
          fail_redirect_url: "https://example.com/fail"
        })
        |> Map.get("errors")
        |> hd()
        |> Map.get("message")

      assert msg =~ "Invalid success_redirect_url: https://example.com/success"
    end

    test "succeeds when different users login from the same ip within burst limits", context do
      config = Sanbase.Accounts.EmailLoginAttempt.config()
      user1 = insert(:user, email: "john@example.com")
      user2 = insert(:user, email: "jane@example.com")

      # Create attempts just under the IP burst limit
      attempts_per_user = div(config.allowed_ip_burst_attempts - 1, 2)

      for _ <- 1..attempts_per_user,
          do: insert(:email_login_attempt, user: user1, ip_address: "127.0.0.1")

      for _ <- 1..attempts_per_user,
          do: insert(:email_login_attempt, user: user2, ip_address: "127.0.0.1")

      # Total attempts still under the burst limit
      result =
        context.conn
        |> Plug.Conn.put_req_header("origin", "https://app.santiment.net")
        |> email_login(%{email: "john@example.com"})
        |> get_in(["data", "emailLogin"])

      assert result["success"]
    end

    test "fails if the user has attempted to login more than user burst limit having the same email",
         context do
      config = Sanbase.Accounts.EmailLoginAttempt.config()
      user = insert(:user, email: "john@example.com")

      # Exceed user burst limit
      for _ <- 1..(config.allowed_user_burst_attempts + 1),
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

    test "fails if the user has attempted to login more than IP burst limit having the same ip",
         context do
      config = Sanbase.Accounts.EmailLoginAttempt.config()
      user1 = insert(:user, email: "john@example.com")
      user2 = insert(:user, email: "jane@example.com")

      # Exceed IP burst limit by creating one more attempt than allowed
      attempts_per_user = div(config.allowed_ip_burst_attempts + 1, 2)

      for _ <- 1..attempts_per_user,
          do: insert(:email_login_attempt, user: user1, ip_address: "127.0.0.1")

      for _ <- 1..(config.allowed_ip_burst_attempts + 1 - attempts_per_user),
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

    test "fails if IP exceeds burst limit before user creation (prevents user pollution)",
         context do
      config = Sanbase.Accounts.EmailLoginAttempt.config()
      test_ip = "127.0.0.1"

      for i <- 1..(config.allowed_ip_burst_attempts + 1) do
        existing_user = insert(:user, email: "user#{i}@example.com")
        {:ok, _} = Sanbase.Accounts.AccessAttempt.create("email_login", existing_user, test_ip)
      end

      # Verify we've exceeded the IP burst limit
      ip_check_result = Sanbase.Accounts.EmailLoginAttempt.check_ip_attempt_limit(test_ip)
      assert ip_check_result == {:error, :too_many_burst_attempts}

      # Generate a unique email to avoid conflicts with other tests
      unique_email = "newuser#{System.unique_integer([:positive])}@example.com"

      # Now try to send email login for a completely new email - this should be blocked by IP rate limiting
      response =
        context.conn
        |> Plug.Conn.put_req_header("origin", "https://app.santiment.net")
        |> email_login(%{email: unique_email})

      assert response["errors"] != nil

      assert Enum.any?(response["errors"], fn error ->
               String.contains?(error["message"], "Too many login attempts")
             end)

      # Verify the user doesn't exist in the database
      assert {:error, _} = Sanbase.Accounts.User.by_email(unique_email)
    end

    test "fails if IP exceeds daily limit before user creation", context do
      config = Sanbase.Accounts.EmailLoginAttempt.config()
      test_ip = "127.0.0.1"

      # Create attempts from past (to avoid burst limit interference) that exceed daily limit
      past_time = DateTime.utc_now() |> DateTime.add(-10, :minute)

      for i <- 1..(config.allowed_ip_daily_attempts + 1) do
        existing_user = insert(:user, email: "dailyuser#{i}@example.com")

        {:ok, attempt} =
          Sanbase.Accounts.AccessAttempt.create("email_login", existing_user, test_ip)

        from(a in Sanbase.Accounts.AccessAttempt, where: a.id == ^attempt.id)
        |> Sanbase.Repo.update_all(set: [inserted_at: past_time])
      end

      user_count_before = Sanbase.Repo.aggregate(Sanbase.Accounts.User, :count, :id)

      response =
        context.conn
        |> Plug.Conn.put_req_header("origin", "https://app.santiment.net")
        |> Plug.Conn.put_req_header("x-forwarded-for", test_ip)
        |> email_login(%{email: "newdailyuser@example.com"})

      msg = response["errors"] |> hd() |> Map.get("message")

      user_count_after = Sanbase.Repo.aggregate(Sanbase.Accounts.User, :count, :id)

      assert msg != nil and msg =~ "Too many login attempts"
      assert user_count_before == user_count_after
      assert {:error, _} = Sanbase.Accounts.User.by_email("newdailyuser@example.com")
    end
  end

  defp email_login_verify_mutation(user) do
    """
    mutation {
      emailLoginVerify(email: "#{user.email}", token: "#{user.email_token}") {
        user {
          email
          firstLogin
        }
        accessToken
      }
    }
    """
  end
end
