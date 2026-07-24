defmodule SanbaseWeb.CategorizationLiveTest do
  use SanbaseWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  setup do
    {:ok, conn: Sanbase.MetricRegistryHelpers.metric_registry_admin_conn()}
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
