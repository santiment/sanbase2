defmodule SanbaseWeb.DeepResearchShareLiveTest do
  @moduledoc """
  The share route's contract: a public session is readable by ANY logged-in
  user (no admin-panel role), a private/unknown one renders the same
  unavailable state, and no session is readable without logging in.
  """

  use SanbaseWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Sanbase.DeepResearch.Fixtures, only: [completed_session: 2]

  defp shared_session(public?) do
    completed_session(Sanbase.Factory.insert(:user), public?: public?)
  end

  # A plain logged-in user with NO admin-panel role — share links only require login.
  defp logged_in_conn() do
    user = Sanbase.Factory.insert(:user)
    {:ok, jwt_tokens} = SanbaseWeb.Guardian.get_jwt_tokens(user)

    Plug.Test.init_test_session(Phoenix.ConnTest.build_conn(), jwt_tokens)
  end

  test "a public session is viewable by any logged-in user" do
    session = shared_session(true)

    {:ok, _view, html} = live(logged_in_conn(), "/deep_research/shared/#{session.id}")

    assert html =~ "Shared research session"
    assert html =~ "ETH drivers?"
    assert html =~ "Fees fell."
    refute html =~ "dr-composer"
  end

  test "a private session renders the unavailable state" do
    session = shared_session(false)

    {:ok, _view, html} = live(logged_in_conn(), "/deep_research/shared/#{session.id}")

    assert html =~ "not available"
    refute html =~ "Fees fell."
  end

  test "an unknown id renders the unavailable state" do
    {:ok, _view, html} =
      live(logged_in_conn(), "/deep_research/shared/#{Ecto.UUID.generate()}")

    assert html =~ "not available"
  end

  test "an unauthenticated visitor is redirected to login" do
    session = shared_session(true)
    conn = Plug.Test.init_test_session(Phoenix.ConnTest.build_conn(), %{})

    assert {:error, {:redirect, %{to: "/admin_auth/login"}}} =
             live(conn, "/deep_research/shared/#{session.id}")
  end
end
