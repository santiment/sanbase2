defmodule SanbaseWeb.AvailableMetricsControllerTest do
  # A missing or non-JSON filter crashed export/2
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

  test "GET /export_available_metrics with a JSON object filter returns the CSV", %{conn: conn} do
    conn = get(conn, "/export_available_metrics", %{"filter" => "{}"})

    assert conn.status == 200
    assert ["text/csv" <> _] = get_resp_header(conn, "content-type")
    assert [_header | _rows] = String.split(conn.resp_body, "\n", trim: true)
  end
end
