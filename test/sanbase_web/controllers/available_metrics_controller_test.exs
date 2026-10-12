defmodule SanbaseWeb.AvailableMetricsControllerTest do
  # SANBASE-BACKEND-PROD-7ST: a missing or non-JSON filter crashed export/2
  use SanbaseWeb.ConnCase, async: true

  @moduletag capture_log: true

  for {name, params} <- [
        {"without a filter", %{}},
        {"with a non-JSON filter", %{"filter" => "not-a-json{"}}
      ] do
    test "GET /export_available_metrics #{name} returns 400", %{conn: conn} do
      conn = get(conn, "/export_available_metrics", unquote(Macro.escape(params)))

      assert conn.status == 400
    end
  end
end
