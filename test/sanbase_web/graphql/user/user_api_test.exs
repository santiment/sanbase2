defmodule SanbaseWeb.Graphql.UserApiTest do
  use SanbaseWeb.ConnCase, async: false

  import Mockery
  import Mock
  import SanbaseWeb.Graphql.TestHelpers
  import ExUnit.CaptureLog
  import Sanbase.Factory

  alias Sanbase.Accounts.User
  alias Sanbase.Repo
  alias Sanbase.Billing.Subscription.SignUpTrial
  alias Sanbase.Auth.User.UniswapStaking

  setup_with_mocks([
    {SignUpTrial, [:passtrough], [create_trial_subscription: fn _ -> {:ok, %{}} end]}
  ]) do
    user = insert(:user)

    conn = setup_jwt_auth(build_conn(), user)

    {:ok, conn: conn, user: user}
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

      assert execute_query(conn, query, "currentUser")["sanBalance"] == 0.0
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
      mock(Sanbase.MandrillApi, :send, {:ok, %{}})

      new_email = "new_test_email@santiment.net"

      mutation = """
      mutation {
        changeEmail(email: "#{new_email}") {
          success
        }
      }
      """

      result = execute_mutation(conn, mutation, "changeEmail")

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
      assert error_msg == "Login failed"
    end

    test "trying to verify email_candidate with a valid email_candidate_token", %{conn: conn} do
      {:ok, user} =
        insert(:user, email: "example@santiment.net")
        |> User.update_email_candidate("example+foo@santiment.net")

      mutation = """
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

      result = execute_mutation(conn, mutation, "emailChangeVerify")
      user = Repo.get_by(User, email: user.email_candidate)

      assert result["token"] != nil
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
        |> User.update_email_candidate("example+foo@santiment.net")

      generated_at =
        Timex.shift(NaiveDateTime.utc_now(), days: -2) |> NaiveDateTime.truncate(:second)

      user =
        user
        |> Ecto.Changeset.change(email_candidate_token_generated_at: generated_at)
        |> Repo.update!()

      mutation = """
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

      error_msg = execute_mutation_with_error(conn, mutation)
      assert error_msg == "Login failed"
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
      user = Repo.get_by(User, email: user.email)

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
         %{
           conn: conn
         } do
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

    test "with not registered user that staked >= 2000 SAN in Uniswap, create free subscription",
         context do
      {:ok, user} =
        insert(:user, email: "example@santiment.net", is_registered: false)
        |> User.update_email_token()

      Sanbase.Mock.prepare_mock2(&UniswapStaking.fetch_uniswap_san_staked_user/1, 2001)
      |> Sanbase.Mock.run_with_mocks(fn ->
        mutation = email_login_verify_mutation(user)
        result = execute_mutation(context.conn, mutation, "emailLoginVerify")

        assert result["user"]["email"] == user.email
        assert Sanbase.Billing.user_has_active_sanbase_subscriptions?(user.id)
        assert Repo.get(User, user.id).is_registered
      end)
    end

    test "with registered user that staked >= 2000 SAN in Uniswap, create free subscription",
         context do
      {:ok, user} =
        insert(:user, email: "example@santiment.net", is_registered: true)
        |> User.update_email_token()

      Sanbase.Mock.prepare_mock2(&UniswapStaking.fetch_uniswap_san_staked_user/1, 2001)
      |> Sanbase.Mock.run_with_mocks(fn ->
        mutation = email_login_verify_mutation(user)
        result = execute_mutation(context.conn, mutation, "emailLoginVerify")

        assert result["user"]["email"] == user.email
        assert Sanbase.Billing.user_has_active_sanbase_subscriptions?(user.id)
        assert Repo.get(User, user.id).is_registered
      end)
    end

    test "with user that staked >= 2000 SAN in Uniswap that have sanbase subscription, create trial subscription",
         context do
      {:ok, user} =
        insert(:user, email: "example@santiment.net", is_registered: false)
        |> User.update_email_token()

      insert(:subscription_pro_sanbase, user: user, stripe_id: "123")

      Sanbase.Mock.prepare_mock2(&UniswapStaking.fetch_uniswap_san_staked_user/1, 2001)
      |> Sanbase.Mock.run_with_mocks(fn ->
        mutation = email_login_verify_mutation(user)
        result = execute_mutation(context.conn, mutation, "emailLoginVerify")

        assert result["user"]["email"] == user.email
        assert Sanbase.Billing.list_liquidity_subscriptions() == []
        assert Repo.get(User, user.id).is_registered
        assert_called(SignUpTrial.create_trial_subscription(user.id))
      end)
    end

    test "with user that staked < 2000 SAN in Uniswap, create trial subscription", context do
      {:ok, user} =
        insert(:user, email: "example@santiment.net", is_registered: false)
        |> User.update_email_token()

      Sanbase.Mock.prepare_mock2(&UniswapStaking.fetch_uniswap_san_staked_user/1, 1999)
      |> Sanbase.Mock.run_with_mocks(fn ->
        mutation = email_login_verify_mutation(user)
        result = execute_mutation(context.conn, mutation, "emailLoginVerify")

        assert result["user"]["email"] == user.email
        assert Sanbase.Billing.list_liquidity_subscriptions() == []
        assert Repo.get(User, user.id).is_registered
        assert_called(SignUpTrial.create_trial_subscription(user.id))
      end)
    end
  end

  describe "Email login" do
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
                   "`something invalid` is not a valid URL. Reason: it is missing scheme (e.g. missing https:// part)"
                 ]
               }
    end
  end

  defp email_login_verify_mutation(user) do
    """
    mutation {
      emailLoginVerify(email: "#{user.email}", token: "#{user.email_token}") {
        user {
          email
        }
        token
      }
    }
    """
  end
end
