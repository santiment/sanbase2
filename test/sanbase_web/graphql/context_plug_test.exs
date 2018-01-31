defmodule SanbaseWeb.Graphql.ContextPlugTest do
  use SanbaseWeb.ConnCase

  import ExUnit.CaptureLog
  import SanbaseWeb.Graphql.TestHelpers

  alias Sanbase.Auth.User
  alias Sanbase.Repo
  alias SanbaseWeb.Graphql.ContextPlug

  test "loading the user from the current token", %{conn: conn} do
    user =
      %User{salt: User.generate_salt()}
      |> Repo.insert!()

    conn = setup_jwt_auth(conn, user)

    assert conn.private[:absinthe] == %{
             context: %{auth: %{auth_method: :user_token, current_user: user}}
           }
  end

  test "verifying the user's salt when loading", %{conn: conn} do
    user =
      %User{salt: User.generate_salt()}
      |> Repo.insert!()

    conn = setup_jwt_auth(conn, user)

    user
    |> Ecto.Changeset.change(salt: User.generate_salt())
    |> Repo.update!()

    logs =
      capture_log(fn ->
        conn = ContextPlug.call(conn, %{})

        assert conn.private[:absinthe] == %{context: %{}}
      end)

    assert logs =~ ~r/Invalid bearer token/
  end
end
