defmodule SanbaseWeb.MetricRegistryController do
  use SanbaseWeb, :controller

  def export_json(conn, _params) do
    conn
    |> resp(200, "ok")
    |> send_resp()
  end

  defp get_metric_registry_json() do
    Sanbase.Metric.Registry.all()
  end
end
