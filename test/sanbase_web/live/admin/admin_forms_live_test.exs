defmodule SanbaseWeb.Admin.AdminFormsLiveTest do
  use SanbaseWeb.ConnCase

  import Phoenix.LiveViewTest
  import Sanbase.Factory

  setup do
    user = insert(:user)
    admin_role = insert(:role_admin_panel_viewer)
    Sanbase.Accounts.UserRole.create(user.id, admin_role.id)
    {:ok, jwt_tokens} = SanbaseWeb.Guardian.get_jwt_tokens(user)
    conn = Plug.Test.init_test_session(build_conn(), jwt_tokens)
    {:ok, conn: conn}
  end

  test "lists the deep research agent with a link to its page", %{conn: conn} do
    {:ok, view, html} = live(conn, "/admin/admin_forms")

    assert html =~ "Deep Research Agent"
    assert html =~ "cited report"

    assert has_element?(view, ~s|a[href="/admin/deep_research"][target="_blank"]|, "Open")
  end
end
