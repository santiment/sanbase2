defmodule SanbaseWeb.Graphql.EmailLoginApiTest do
  use SanbaseWeb.ConnCase

  import Mock
  import Mockery
  import SanbaseWeb.Graphql.TestHelpers
  import Sanbase.Factory

  alias Sanbase.Accounts.User
  alias Sanbase.Repo
  alias Sanbase.Billing.Subscription.SignUpTrial
  alias Sanbase.Accounts.User.UniswapStaking

  setup_with_mocks([
    {SignUpTrial, [], [create_trial_subscription: fn _ -> {:ok, %{}} end]}
  ]) do
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
      {Sanbase.MandrillApi, [], [send: fn _, _, _, _ -> {:ok, %{}} end]}
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

    test "emailLogin returns true if the login email was sent successfully", context do
      result =
        email_login(context.conn, %{email: "john@example.com"})
        |> get_in(["data", "emailLogin"])

      assert {:ok, %User{}} = User.by_email("john@example.com")
      assert result["success"]
      assert result["firstLogin"]
    end

    test "emailLogin with newsletter subscription adds newsletter subscription param", context do
      result =
        email_login(context.conn, %{email: "john@example.com", subscribeToWeeklyNewsletter: true})
        |> get_in(["data", "emailLogin"])

      assert {:ok, %User{}} = User.by_email("john@example.com")
      assert result["success"]
      assert result["firstLogin"]

      assert_called(
        Sanbase.MandrillApi.send(
          :_,
          "john@example.com",
          :meck.is(fn %{LOGIN_LINK: login_link} ->
            assert login_link =~ "subscribe_to_weekly_newsletter=true"
          end),
          :_
        )
      )
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
