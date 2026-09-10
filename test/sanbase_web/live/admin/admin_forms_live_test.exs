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

  @card "#form-info-deep-research-agent"

  test "lists the deep research agent with a link to its page", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/admin/admin_forms")

    assert has_element?(view, @card, "Deep Research Agent")
    assert has_element?(view, @card, "cited report")

    assert has_element?(
             view,
             ~s|#{@card} a[href="/admin/deep_research"][target="_blank"]|,
             "Open"
           )
  end
end
