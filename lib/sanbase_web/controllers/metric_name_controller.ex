defmodule SanbaseWeb.MetricNameController do
  use SanbaseWeb, :controller

  require Logger

  def api_metric_name_mapping(conn, _params) do
    map = Sanbase.Clickhouse.MetricAdapter.Registry.name_to_metric_map()

    data =
      Enum.map(map, fn {k, v} ->
        %{public_name: k, internal_name: v}
        |> Jason.encode!()
      end)
      |> Enum.join("\n")

    conn
    |> put_resp_header("content-type", "application/json; charset=utf-8")
    |> Plug.Conn.send_resp(200, data)
  end
end
