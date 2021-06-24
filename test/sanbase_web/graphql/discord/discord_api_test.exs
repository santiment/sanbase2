defmodule SanbaseWeb.Graphql.DiscordApiTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  setup do
    user = insert(:user)
    conn = setup_jwt_auth(build_conn(), user)
    {:ok, conn: conn, user: user}
  end

  describe "#addToProRoleInDiscord" do
    test "when user is pro - succeeds", context do
      insert(:subscription_pro_sanbase, user: context.user)
      resp_json = [%{"user" => %{"id" => "12345"}, "roles" => []}] |> Jason.encode!()
      http_resp = %HTTPoison.Response{body: resp_json, status_code: 200}

      Sanbase.Mock.prepare_mock2(&HTTPoison.get/2, {:ok, http_resp})
      |> Sanbase.Mock.prepare_mock2(
        &HTTPoison.put/3,
        {:ok, %HTTPoison.Response{body: "", status_code: 204}}
      )
      |> Sanbase.Mock.run_with_mocks(fn ->
        assert execute_mutation(
                 context.conn,
                 pro_role_mutation("test_user"),
                 "addToProRoleInDiscord"
               )
      end)
    end

    test "when user is pro but trialing - shows upgrade message", context do
      insert(:subscription_pro_sanbase, user: context.user, status: "trialing")
      resp_json = [%{"user" => %{"id" => "12345"}, "roles" => []}] |> Jason.encode!()
      http_resp = %HTTPoison.Response{body: resp_json, status_code: 200}

      Sanbase.Mock.prepare_mock2(&HTTPoison.get/2, {:ok, http_resp})
      |> Sanbase.Mock.prepare_mock2(
        &HTTPoison.put/3,
        {:ok, %HTTPoison.Response{body: "", status_code: 204}}
      )
      |> Sanbase.Mock.run_with_mocks(fn ->
        error_msg = execute_mutation_with_error(context.conn, pro_role_mutation("test_user"))
        assert error_msg =~ "Please, upgrade to Sanbase PRO plan or higher!"
      end)
    end

    test "when user is not pro - shows upgrade message", context do
      resp_json = [%{"user" => %{"id" => "12345"}}] |> Jason.encode!()
      http_resp = %HTTPoison.Response{body: resp_json, status_code: 200}

      Sanbase.Mock.prepare_mock2(&HTTPoison.get/2, {:ok, http_resp})
      |> Sanbase.Mock.prepare_mock2(
        &HTTPoison.put/3,
        {:ok, %HTTPoison.Response{body: "", status_code: 204}}
      )
      |> Sanbase.Mock.run_with_mocks(fn ->
        error_msg = execute_mutation_with_error(context.conn, pro_role_mutation("test_user"))
        assert error_msg =~ "Please, upgrade to Sanbase PRO plan or higher!"
      end)
    end

    test "when user already have discord pro role - show proper message", context do
      insert(:subscription_pro_sanbase, user: context.user)

      resp_json =
        [%{"user" => %{"id" => "12345"}, "roles" => ["532833809947951105"]}] |> Jason.encode!()

      http_resp = %HTTPoison.Response{body: resp_json, status_code: 200}

      Sanbase.Mock.prepare_mock2(&HTTPoison.get/2, {:ok, http_resp})
      |> Sanbase.Mock.prepare_mock2(
        &HTTPoison.put/3,
        {:ok, %HTTPoison.Response{body: "", status_code: 204}}
      )
      |> Sanbase.Mock.run_with_mocks(fn ->
        error_msg = execute_mutation_with_error(context.conn, pro_role_mutation("test_user"))
        assert error_msg =~ "This username already have a PRO role in our discord server"
      end)
    end

    test "when more than one user is returned - show proper message", context do
      insert(:subscription_pro_sanbase, user: context.user)
      resp_json = [%{"user" => %{"id" => "12345"}}, %{}] |> Jason.encode!()
      http_resp = %HTTPoison.Response{body: resp_json, status_code: 200}

      Sanbase.Mock.prepare_mock2(&HTTPoison.get/2, {:ok, http_resp})
      |> Sanbase.Mock.prepare_mock2(
        &HTTPoison.put/3,
        {:ok, %HTTPoison.Response{body: "", status_code: 204}}
      )
      |> Sanbase.Mock.run_with_mocks(fn ->
        error_msg = execute_mutation_with_error(context.conn, pro_role_mutation("test_user"))
        assert error_msg =~ "Please, provide your exact handle on our discord server"
      end)
    end

    test "when no user is found - show proper message", context do
      insert(:subscription_pro_sanbase, user: context.user)
      resp_json = [] |> Jason.encode!()
      http_resp = %HTTPoison.Response{body: resp_json, status_code: 200}

      Sanbase.Mock.prepare_mock2(&HTTPoison.get/2, {:ok, http_resp})
      |> Sanbase.Mock.prepare_mock2(
        &HTTPoison.put/3,
        {:ok, %HTTPoison.Response{body: "", status_code: 204}}
      )
      |> Sanbase.Mock.run_with_mocks(fn ->
        error_msg = execute_mutation_with_error(context.conn, pro_role_mutation("test_user"))
        assert error_msg =~ "User with this handle is not found on our discord server"
      end)
    end
  end

  def pro_role_mutation(username) do
    """
    mutation {
      addToProRoleInDiscord(discordUsername: "#{username}")
    }
    """
  end
end
