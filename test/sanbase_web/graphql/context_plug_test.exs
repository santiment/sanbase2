defmodule SanbaseWeb.Graphql.ContextPlugTest do
  use SanbaseWeb.ConnCase, async: false

  import SanbaseWeb.Graphql.TestHelpers
  import Sanbase.Factory
  @moduletag capture_log: true

  alias Sanbase.Auth.User
  alias Sanbase.Repo
  alias SanbaseWeb.Graphql.ContextPlug
  alias Sanbase.Auth.Apikey
  alias Sanbase.Billing.Product

  test "loading the user from the current token", %{conn: conn} do
    user =
      %User{
        salt: User.generate_salt(),
        privacy_policy_accepted: true,
        test_san_balance: Decimal.new(500_000)
      }
      |> Repo.insert!()

    conn = setup_jwt_auth(conn, user)

    conn_context = conn.private.absinthe.context

    assert conn_context.auth == %{
             auth_method: :user_token,
             current_user: user,
             san_balance: 500_000.0,
             subscription: nil
           }

    assert conn_context.remote_ip == {127, 0, 0, 1}
    assert conn_context.permissions == User.full_permissions()
  end

  test "verifying the user's salt when loading", %{conn: conn} do
    user =
      %User{salt: User.generate_salt(), privacy_policy_accepted: true}
      |> Repo.insert!()

    conn = setup_jwt_auth(conn, user)

    user
    |> Ecto.Changeset.change(salt: User.generate_salt())
    |> Repo.update!()

    conn = ContextPlug.call(conn, %{})

    {:ok, result} = conn.resp_body |> Jason.decode()

    assert conn.status == 400
    assert result["errors"]["details"] == "Bad authorization header: Invalid JSON Web Token (JWT)"
  end

  test "invalid token returns error" do
    conn =
      build_conn()
      |> put_req_header("authorization", "Bearer some_random_not_correct_token")

    conn = ContextPlug.call(conn, %{})
    {:ok, result} = conn.resp_body |> Jason.decode()

    assert conn.status == 400
    assert result["errors"]["details"] == "Bad authorization header: Invalid JSON Web Token (JWT)"
  end

  test "invalid basic auth returns error" do
    conn =
      build_conn()
      |> put_req_header("authorization", "Basic gibberish")

    conn = ContextPlug.call(conn, %{})

    {:ok, result} = conn.resp_body |> Jason.decode()

    assert conn.status == 400

    assert result["errors"]["details"] ==
             "Bad authorization header: Invalid basic authorization header credentials"
  end

  test "not existing apikey returns error" do
    apikey = "random_apikey"

    conn =
      build_conn()
      |> put_req_header("authorization", "Apikey #{apikey}")

    conn = ContextPlug.call(conn, %{})

    {:ok, result} = conn.resp_body |> Jason.decode()

    assert conn.status == 400

    assert result["errors"]["details"] ==
             "Bad authorization header: Apikey '#{apikey}' is not valid"
  end

  test "malformed apikey returns error" do
    apikey = "api_key_must_contain_single_underscore"

    conn =
      build_conn()
      |> put_req_header(
        "authorization",
        "Apikey #{apikey}"
      )

    conn = ContextPlug.call(conn, %{})
    {:ok, result} = conn.resp_body |> Jason.decode()

    assert conn.status == 400

    assert result["errors"]["details"] =~
             "Bad authorization header: Apikey '#{apikey}' is malformed"
  end

  test "unsupported/mistyped authorization header returns error" do
    conn =
      build_conn()
      |> put_req_header(
        "authorization",
        "Aapikey api_key_must_contain_single_underscore"
      )

    conn = ContextPlug.call(conn, %{})

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
      |> put_req_header(
        "authorization",
        "null"
      )

    conn = ContextPlug.call(conn, %{})

    conn_context = conn.private.absinthe.context

    refute Map.has_key?(conn_context, :auth)
    assert conn_context.remote_ip == {127, 0, 0, 1}
    assert conn_context.permissions == User.no_permissions()
  end

  test "empty authorization header passes" do
    conn =
      build_conn()
      |> put_req_header(
        "authorization",
        ""
      )

    conn = ContextPlug.call(conn, %{})

    conn_context = conn.private.absinthe.context

    refute Map.has_key?(conn_context, :auth)
    assert conn_context.remote_ip == {127, 0, 0, 1}
    assert conn_context.permissions == User.no_permissions()
  end

  test "no authorization header passes" do
    conn = build_conn()

    conn = ContextPlug.call(conn, %{})

    conn_context = conn.private.absinthe.context

    refute Map.has_key?(conn_context, :auth)
    assert conn_context.remote_ip == {127, 0, 0, 1}
    assert conn_context.permissions == User.no_permissions()
  end

  describe "product is set in context" do
    test "when no authorization and Origin sanbase - product is SANBase" do
      conn =
        build_conn()
        |> put_req_header(
          "origin",
          "https://app.santiment.net"
        )

      conn = ContextPlug.call(conn, %{})

      conn_context = conn.private.absinthe.context

      assert conn_context.product == Product.product_sanbase()
    end

    test "when no authorization and other Origin - product is SANApi" do
      conn = ContextPlug.call(build_conn(), %{})

      conn_context = conn.private.absinthe.context

      assert conn_context.product == Product.product_api()
    end

    test "when JWT auth - product is SANBase" do
      user = insert(:user)
      conn = setup_jwt_auth(build_conn(), user)

      conn_context = conn.private.absinthe.context

      assert conn_context.product == Product.product_sanbase()
    end

    test "when Apikey and User-Agent is from sheets - product is SANsheets" do
      user = insert(:user)
      {:ok, apikey} = Apikey.generate_apikey(user)

      conn =
        build_conn()
        |> put_req_header(
          "user-agent",
          "Mozilla/5.0 (compatible; Google-Apps-Script)"
        )

      conn = setup_apikey_auth(conn, apikey)

      conn_context = conn.private.absinthe.context

      assert conn_context.product == Product.product_sheets()
    end

    test "when Apikey and other User-Agent - product is SANApi" do
      user = insert(:user)
      {:ok, apikey} = Apikey.generate_apikey(user)

      conn = setup_apikey_auth(build_conn(), apikey)

      conn_context = conn.private.absinthe.context

      assert conn_context.product == Product.product_api()
    end
  end
end
