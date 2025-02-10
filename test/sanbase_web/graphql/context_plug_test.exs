defmodule SanbaseWeb.Graphql.ContextPlugTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  alias Sanbase.Accounts.Apikey
  alias Sanbase.Accounts.User
  alias Sanbase.Billing.Product
  alias SanbaseWeb.Graphql.AuthPlug
  alias SanbaseWeb.Graphql.ContextPlug

  @moduletag capture_log: true

  test "loading the user from the current token", %{conn: conn} do
    {:ok, user} = User.create(%{privacy_policy_accepted: true})
    # Do it like this, as the `user` from User.create/1 has `first_login: true`
    # which won't correspond to the one from the AuthPlug as it will again
    # fetch the user and it will no longer be the first login.
    {:ok, user} = Sanbase.Accounts.get_user(user.id)

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
             subscription: nil,
             plan: "FREE"
           }

    assert conn_context.remote_ip == {127, 0, 0, 1}
  end

  test "invalid token returns error" do
    conn =
      build_conn()
      |> get("/get_routed_conn")
      |> put_req_header("authorization", "Bearer some_random_not_correct_token")

    conn = conn |> AuthPlug.call(%{}) |> ContextPlug.call(%{})
    {:ok, result} = Jason.decode(conn.resp_body)

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
    assert conn_context.auth.plan == "FREE"
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

    {:ok, result} = Jason.decode(conn.resp_body)

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
    {:ok, result} = Jason.decode(conn.resp_body)

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

    {:ok, result} = Jason.decode(conn.resp_body)

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
    assert conn_context.auth.plan == "FREE"
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
    assert conn_context.auth.plan == "FREE"
    assert conn_context.remote_ip == {127, 0, 0, 1}
    assert conn_context.permissions == User.Permissions.no_permissions()
  end

  test "no authorization header passes" do
    conn = get(build_conn(), "/get_routed_conn")

    conn = conn |> AuthPlug.call(%{}) |> ContextPlug.call(%{})

    conn_context = conn.private.absinthe.context

    assert Map.has_key?(conn_context, :auth)
    assert conn_context.auth.auth_method == :none
    assert conn_context.auth.plan == "FREE"
    assert conn_context.remote_ip == {127, 0, 0, 1}
    assert conn_context.permissions == User.Permissions.no_permissions()
  end

  describe "product is set in context" do
    test "when no authorization and Origin sanbase - product is Sanbase" do
      conn =
        build_conn()
        |> get("/get_routed_conn")
        |> put_req_header(
          "origin",
          "https://app.santiment.net"
        )

      conn = conn |> AuthPlug.call(%{}) |> ContextPlug.call(%{})

      conn_context = conn.private.absinthe.context

      assert conn_context.requested_product_id == Product.product_sanbase()
      assert conn_context.requested_product == "SANBASE"
      assert conn_context.subscription_product_id == nil
      assert conn_context.subscription_product == nil
    end

    test "when no authorization and other Origin - product is Sanapi" do
      conn =
        build_conn() |> get("/get_routed_conn") |> AuthPlug.call(%{}) |> ContextPlug.call(%{})

      conn_context = conn.private.absinthe.context

      assert conn_context.requested_product_id == Product.product_api()
      assert conn_context.requested_product == "SANAPI"
      assert conn_context.subscription_product_id == nil
      assert conn_context.subscription_product == nil
    end

    test "when JWT auth - product is Sanbase" do
      user = insert(:user)

      conn =
        build_conn()
        |> get("/get_routed_conn")
        |> setup_jwt_auth(user)
        |> AuthPlug.call(%{})
        |> ContextPlug.call(%{})

      conn_context = conn.private.absinthe.context

      assert conn_context.requested_product_id == Product.product_sanbase()
      assert conn_context.requested_product == "SANBASE"
      assert conn_context.subscription_product_id == nil
      assert conn_context.subscription_product == nil
    end

    test "when JWT auth with API Business plan" do
      user = insert(:user, email: "test@example.com")
      insert(:subscription_business_max_monthly, user: user)

      conn =
        build_conn()
        |> get("/get_routed_conn")
        |> setup_jwt_auth(user)
        |> AuthPlug.call(%{})
        |> ContextPlug.call(%{})

      conn_context = conn.private.absinthe.context

      assert conn_context.requested_product_id == Product.product_sanbase()
      assert conn_context.requested_product == "SANBASE"
      assert conn_context.subscription_product_id == Product.product_api()
      assert conn_context.subscription_product == "SANAPI"
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

      conn = conn |> setup_apikey_auth(apikey) |> AuthPlug.call(%{}) |> ContextPlug.call(%{})

      conn_context = conn.private.absinthe.context

      assert conn_context.requested_product_id == Product.product_sanbase()
      assert conn_context.requested_product == "SANBASE"
      assert conn_context.subscription_product_id == Product.product_sanbase()
      assert conn_context.subscription_product == "SANBASE"
    end

    test "when Apikey and other User-Agent - product is Sanapi" do
      user = insert(:user)
      {:ok, apikey} = Apikey.generate_apikey(user)

      conn =
        build_conn()
        |> get("/get_routed_conn")
        |> setup_apikey_auth(apikey)
        |> AuthPlug.call(%{})
        |> ContextPlug.call(%{})

      conn_context = conn.private.absinthe.context

      assert conn_context.requested_product_id == Product.product_api()
      assert conn_context.requested_product == "SANAPI"
      assert conn_context.subscription_product_id == nil
      assert conn_context.subscription_product == nil
    end

    test "when Apikey with Sanbase PRO plan" do
      user = insert(:user)
      insert(:subscription_pro_sanbase, user: user)
      {:ok, apikey} = Apikey.generate_apikey(user)

      conn =
        build_conn()
        |> get("/get_routed_conn")
        |> setup_apikey_auth(apikey)
        |> AuthPlug.call(%{})
        |> ContextPlug.call(%{})

      conn_context = conn.private.absinthe.context

      assert conn_context.requested_product_id == Product.product_api()
      assert conn_context.requested_product == "SANAPI"
      assert conn_context.subscription_product_id == Product.product_sanbase()
      assert conn_context.subscription_product == "SANBASE"
    end
  end
end
