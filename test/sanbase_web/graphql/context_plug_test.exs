defmodule SanbaseWeb.Graphql.ContextPlugTest do
  use SanbaseWeb.ConnCase, async: false

  import SanbaseWeb.Graphql.TestHelpers
  @moduletag capture_log: true

  alias Sanbase.Auth.User
  alias Sanbase.Repo
  alias SanbaseWeb.Graphql.ContextPlug

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

    assert conn_context.auth == %{auth_method: :user_token, current_user: user}
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

    assert conn.status == 400
    assert conn.resp_body == "Bad authorization header: Invalid JSON Web Token (JWT)"
  end

  test "invalid token returns error" do
    conn =
      build_conn()
      |> put_req_header("authorization", "Bearer some_random_not_correct_token")

    conn = ContextPlug.call(conn, %{})
    assert conn.status == 400
    assert conn.resp_body == "Bad authorization header: Invalid JSON Web Token (JWT)"
  end

  test "invalid basic auth returns error" do
    conn =
      build_conn()
      |> put_req_header("authorization", "Basic gibberish")

    conn = ContextPlug.call(conn, %{})
    assert conn.status == 400

    assert conn.resp_body ==
             "Bad authorization header: Invalid basic authorization header credentials"
  end

  test "not existing apikey returns error" do
    apikey = "random_apikey"

    conn =
      build_conn()
      |> put_req_header("authorization", "Apikey #{apikey}")

    conn = ContextPlug.call(conn, %{})
    assert conn.status == 400
    assert conn.resp_body == "Bad authorization header: Apikey '#{apikey}' is not valid"
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
    assert conn.status == 400
    assert conn.resp_body =~ "Bad authorization header: Apikey '#{apikey}' is malformed"
  end

  test "unsupported/mistyped authorization header returns error" do
    conn =
      build_conn()
      |> put_req_header(
        "authorization",
        "Aapikey api_key_must_contain_single_underscore"
      )

    conn = ContextPlug.call(conn, %{})
    assert conn.status == 400

    assert conn.resp_body == """
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
end
