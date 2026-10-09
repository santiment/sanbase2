defmodule SanbaseWeb.AvailableMetricsControllerTest do
  # Reproduces SANBASE-BACKEND-PROD-7ST:
  # Phoenix.ActionClauseError: no function clause matching in
  # SanbaseWeb.AvailableMetricsController.export/2
  #
  # export/2 only matches `%{"filter" => filter_json}`. Crawlers (ClaudeBot etc.) hit
  # GET /export_available_metrics without a query string, which raises and is reported
  # to Sentry. A `filter` that is not valid JSON makes `Jason.decode!/1` raise as well.
  # Both are bad client input and should get a 400 without raising.
  use SanbaseWeb.ConnCase, async: true

  @moduletag capture_log: true

  test "GET /export_available_metrics without a filter returns 400", %{conn: conn} do
    conn = get(conn, "/export_available_metrics")

    assert conn.status == 400
  end

  test "GET /export_available_metrics with non-JSON filter returns 400", %{conn: conn} do
    conn = get(conn, "/export_available_metrics", %{"filter" => "not-a-json{"})

    assert conn.status == 400
  end
end
