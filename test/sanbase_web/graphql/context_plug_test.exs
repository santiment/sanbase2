defmodule SanbaseWeb.Graphql.ContextPlugTest do
  use SanbaseWeb.ConnCase, async: false

  import ExUnit.CaptureLog
  import SanbaseWeb.Graphql.TestHelpers

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

    logs =
      capture_log(fn ->
        conn = ContextPlug.call(conn, %{})

        conn_context = conn.private.absinthe.context
        assert conn_context.remote_ip == {127, 0, 0, 1}
        assert conn_context.permissions == User.no_permissions()
        assert Map.has_key?(conn_context, :query_cache_key)
      end)

    assert logs =~ ~r/Invalid bearer token/
  end
end
