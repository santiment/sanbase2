defmodule SanbaseWeb.MetricNameController do
  use SanbaseWeb, :controller

  alias Sanbase.Model.Project
  require Logger

  def clickhouse_metric_aliases(conn, _params) do
    map = Sanbase.Clickhouse.MetricAdapter.FileHandler.name_to_metric_map()

    data =
      Enum.map(map, fn {k, v} ->
        %{public_name: k, internal_name: v}
      end)

    conn
    |> put_resp_header("content-type", "application/json; charset=utf-8")
    |> Plug.Conn.send_resp(200, data)
  end
end
