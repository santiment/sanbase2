defmodule SanbaseWeb.Auth.ContextPlugTest do
  use SanbaseWeb.ConnCase

  import Plug.Conn
  import ExUnit.CaptureLog

  alias Sanbase.Auth.User
  alias Sanbase.Repo
  alias SanbaseWeb.Auth.ContextPlug

  test "loading the user from the current token", %{conn: conn} do
    user = %User{salt: User.generate_salt()}
    |> Repo.insert!
    {:ok, token, _claims} = SanbaseWeb.Guardian.encode_and_sign(user, %{salt: user.salt})

    conn = conn
    |> put_req_header("authorization", "Bearer " <> token)

    conn = ContextPlug.call(conn, %{})

    assert conn.private[:absinthe] == %{context: %{current_user: user}}
  end

  test "verifying the user's salt when loading", %{conn: conn} do
    user = %User{salt: User.generate_salt()}
    |> Repo.insert!
    {:ok, token, _claims} = SanbaseWeb.Guardian.encode_and_sign(user, %{salt: user.salt})

    conn = conn
    |> put_req_header("authorization", "Bearer " <> token)

    user
    |> Ecto.Changeset.change(salt: User.generate_salt())
    |> Repo.update!

    logs = capture_log(fn ->
      conn = ContextPlug.call(conn, %{})

      assert conn.private[:absinthe] == %{context: %{}}
    end)

    assert logs =~ ~r/Invalid token/
  end
end
