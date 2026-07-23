defmodule SanbaseWeb.CategorizationLiveTest do
  use SanbaseWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Sanbase.Factory

  setup do
    user = insert(:user)
    metric_registry_role = insert(:role_metric_registry_owner)
    admin_role = insert(:role_admin_panel_viewer)
    Sanbase.Accounts.UserRole.create(user.id, metric_registry_role.id)
    Sanbase.Accounts.UserRole.create(user.id, admin_role.id)
    {:ok, jwt_tokens} = SanbaseWeb.Guardian.get_jwt_tokens(user)
    conn = Plug.Test.init_test_session(build_conn(), jwt_tokens)

    {:ok, conn: conn}
  end

  test "renders the metrics table", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/admin/metric_registry/categorization")

    assert has_element?(view, "div", "Metric Categorization")
    assert has_element?(view, "td div", "price_usd")
  end

  test "filters by not-categorized status", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/admin/metric_registry/categorization")

    view
    |> element("form[phx-change=\"filter\"]")
    |> render_change(%{"status" => "not_categorized"})

    assert has_element?(view, "td div", "price_usd")
  end
end
