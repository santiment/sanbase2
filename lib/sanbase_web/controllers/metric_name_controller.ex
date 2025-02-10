defmodule SanbaseWeb.MetricNameController do
  use SanbaseWeb, :controller

  require Logger

  def api_metric_name_mapping(conn, _params) do
    map = Sanbase.Clickhouse.MetricAdapter.Registry.name_to_metric_map()

    data =
      Enum.map_join(map, "\n", fn {k, v} ->
        Jason.encode!(%{public_name: k, internal_name: v})
      end)

    conn
    |> put_resp_header("content-type", "application/json; charset=utf-8")
    |> Plug.Conn.send_resp(200, data)
  end
end
