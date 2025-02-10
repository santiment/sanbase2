defmodule SanbaseWeb.AvailableMetricsController do
  @moduledoc """
  Controller for the available metrics export.
  """

  use SanbaseWeb, :controller

  def export(conn, %{"filter" => filter_json}) do
    conn
    |> put_resp_content_type("text/csv")
    |> put_resp_header(
      "content-disposition",
      "attachment; filename=\"santiment_available_metrics.csv\""
    )
    |> send_resp(200, csv_content(filter_json))
  end

  defp csv_content(filter_json) do
    filter = Jason.decode!(filter_json)
    metrics_map = Sanbase.AvailableMetrics.get_metrics_map()

    metrics =
      Sanbase.AvailableMetrics.apply_filters(metrics_map, filter)

    csv_content =
      Enum.map(metrics, fn map ->
        [
          map.metric,
          map.internal_name,
          map.frequency_seconds,
          Enum.map(map.docs, & &1.link),
          map.available_assets
        ]
      end)

    csv_content =
      [["Metric", "Internal Name", "Frequency", "Docs", "Available Assets"]] ++ csv_content

    NimbleCSV.RFC4180.dump_to_iodata(csv_content)
  end
end
