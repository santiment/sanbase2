defmodule SanbaseWeb.Graphql.ContextPlugTest do
  use SanbaseWeb.ConnCase, async: false

  import SanbaseWeb.Graphql.TestHelpers
  import Sanbase.Factory
  @moduletag capture_log: true

  alias Sanbase.Accounts.User
  alias Sanbase.Repo
  alias SanbaseWeb.Graphql.{AuthPlug, ContextPlug}
  alias Sanbase.Accounts.Apikey
  alias Sanbase.Billing.{Subscription, Product}

  test "loading the user from the current token", %{conn: conn} do
    user =
      %User{
        salt: User.generate_salt(),
        privacy_policy_accepted: true
      }
      |> Repo.insert!()

    conn =
      conn
      |> get("/get_routed_conn")
      |> setup_jwt_auth(user)
      |> AuthPlug.call(%{})
      |> ContextPlug.call(%{})

    conn_context = conn.private.absinthe.context

    assert conn_context.auth == %{
             auth_method: :user_token,
             current_user: user,
             subscription: Subscription.free_subscription(),
             plan: :free
           }

    assert conn_context.remote_ip == {127, 0, 0, 1}
  end

  test "invalid token returns error" do
    conn =
      build_conn()
      |> get("/get_routed_conn")
      |> put_req_header("authorization", "Bearer some_random_not_correct_token")

    conn = conn |> AuthPlug.call(%{}) |> ContextPlug.call(%{})
    {:ok, result} = conn.resp_body |> Jason.decode()

    assert conn.status == 400
    assert result["errors"]["details"] == "Invalid JSON Web Token (JWT)"
  end

  test "invalid basic auth does not return error but uses anon user" do
    conn =
      build_conn()
      |> get("/get_routed_conn")
      |> put_req_header("authorization", "Basic gibberish")

    conn = conn |> AuthPlug.call(%{}) |> ContextPlug.call(%{})
    conn_context = conn.private.absinthe.context

    assert Map.has_key?(conn_context, :auth)
    assert conn_context.auth.auth_method == :none
    assert conn_context.auth.plan == :free
    assert conn_context.remote_ip == {127, 0, 0, 1}
    assert conn_context.permissions == User.Permissions.no_permissions()
  end

  test "not existing apikey returns error" do
    apikey = "random_apikey"

    conn =
      build_conn()
      |> get("/get_routed_conn")
      |> put_req_header("authorization", "Apikey #{apikey}")

    conn = conn |> AuthPlug.call(%{}) |> ContextPlug.call(%{})

    {:ok, result} = conn.resp_body |> Jason.decode()

    assert conn.status == 400

    assert result["errors"]["details"] ==
             "Apikey '#{Apikey.mask_apikey(apikey)}' is not valid"
  end

  test "malformed apikey returns error" do
    apikey = "api_key_must_contain_single_underscore"

    conn =
      build_conn()
      |> get("/get_routed_conn")
      |> put_req_header(
        "authorization",
        "Apikey #{apikey}"
      )

    conn = conn |> AuthPlug.call(%{}) |> ContextPlug.call(%{})
    {:ok, result} = conn.resp_body |> Jason.decode()

    assert conn.status == 400

    assert result["errors"]["details"] =~
             "Apikey '#{apikey}' is malformed"
  end

  test "unsupported/mistyped authorization header returns error" do
    conn =
      build_conn()
      |> get("/get_routed_conn")
      |> put_req_header(
        "authorization",
        "Aapikey api_key_must_contain_single_underscore"
      )

    conn = conn |> AuthPlug.call(%{}) |> ContextPlug.call(%{})

    {:ok, result} = conn.resp_body |> Jason.decode()

    assert conn.status == 400

    assert result["errors"]["details"] == """
           Unsupported authorization header value: \"Aapikey api_key_must_contain_single_underscore\".
           The supported formats of the authorization header are:
             \"Bearer <JWT>\"
             \"Apikey <apikey>\"
             \"Basic <basic>\"
           """
  end

  test "null authorization header passes" do
    conn =
      build_conn()
      |> get("/get_routed_conn")
      |> put_req_header(
        "authorization",
        "null"
      )

    conn = conn |> AuthPlug.call(%{}) |> ContextPlug.call(%{})

    conn_context = conn.private.absinthe.context

    assert Map.has_key?(conn_context, :auth)
    assert conn_context.auth.auth_method == :none
    assert conn_context.auth.plan == :free
    assert conn_context.remote_ip == {127, 0, 0, 1}
    assert conn_context.permissions == User.Permissions.no_permissions()
  end

  test "empty authorization header passes" do
    conn =
      build_conn()
      |> get("/get_routed_conn")
      |> put_req_header(
        "authorization",
        ""
      )

    conn = conn |> AuthPlug.call(%{}) |> ContextPlug.call(%{})

    conn_context = conn.private.absinthe.context

    assert Map.has_key?(conn_context, :auth)
    assert conn_context.auth.auth_method == :none
    assert conn_context.auth.plan == :free
    assert conn_context.remote_ip == {127, 0, 0, 1}
    assert conn_context.permissions == User.Permissions.no_permissions()
  end

  test "no authorization header passes" do
    conn =
      build_conn()
      |> get("/get_routed_conn")

    conn = conn |> AuthPlug.call(%{}) |> ContextPlug.call(%{})

    conn_context = conn.private.absinthe.context

    assert Map.has_key?(conn_context, :auth)
    assert conn_context.auth.auth_method == :none
    assert conn_context.auth.plan == :free
    assert conn_context.remote_ip == {127, 0, 0, 1}
    assert conn_context.permissions == User.Permissions.no_permissions()
  end

  describe "product is set in context" do
    test "when no authorization and Origin sanbase - product is SANBase" do
      conn =
        build_conn()
        |> get("/get_routed_conn")
        |> put_req_header(
          "origin",
          "https://app.santiment.net"
        )

      conn = conn |> AuthPlug.call(%{}) |> ContextPlug.call(%{})

      conn_context = conn.private.absinthe.context

      assert conn_context.product_id == Product.product_sanbase()
    end

    test "when no authorization and other Origin - product is SanAPI" do
      conn =
        build_conn() |> get("/get_routed_conn") |> AuthPlug.call(%{}) |> ContextPlug.call(%{})

      conn_context = conn.private.absinthe.context

      assert conn_context.product_id == Product.product_api()
    end

    test "when JWT auth - product is SANBase" do
      user = insert(:user)

      conn =
        build_conn()
        |> get("/get_routed_conn")
        |> setup_jwt_auth(user)
        |> AuthPlug.call(%{})
        |> ContextPlug.call(%{})

      conn_context = conn.private.absinthe.context

      assert conn_context.product_id == Product.product_sanbase()
    end

    test "when Apikey and User-Agent is from sheets - product is sanbase" do
      user = insert(:user)
      insert(:subscription_pro_sanbase, user: user)
      {:ok, apikey} = Apikey.generate_apikey(user)

      conn =
        build_conn()
        |> get("/get_routed_conn")
        |> put_req_header(
          "user-agent",
          "Mozilla/5.0 (compatible; Google-Apps-Script)"
        )

      conn = setup_apikey_auth(conn, apikey) |> AuthPlug.call(%{}) |> ContextPlug.call(%{})

      conn_context = conn.private.absinthe.context

      assert conn_context.product_id == Product.product_sanbase()
    end

    test "when Apikey and other User-Agent - product is SanAPI" do
      user = insert(:user)
      {:ok, apikey} = Apikey.generate_apikey(user)

      conn =
        build_conn()
        |> get("/get_routed_conn")
        |> setup_apikey_auth(apikey)
        |> AuthPlug.call(%{})
        |> ContextPlug.call(%{})

      conn_context = conn.private.absinthe.context

      assert conn_context.product_id == Product.product_api()
    end
  end
end
