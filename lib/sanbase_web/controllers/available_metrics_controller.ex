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

  # The UI always sends a "filter" param (the download link serializes the
  # current filter, defaulting to "{}"). A request without it can only be a
  # direct/bot hit, so return 400 instead of raising Phoenix.ActionClauseError
  # or doing the work of building a full CSV.
  def export(conn, _params) do
    send_resp(conn, 400, "Missing required \"filter\" parameter")
  end

  defp csv_content(filter_json) do
    filter = Jason.decode!(filter_json)
    metrics_map = Sanbase.AvailableMetrics.get_metrics_map()

    metrics =
      Sanbase.AvailableMetrics.apply_filters(metrics_map, filter)

    csv_content =
      metrics
      |> Enum.map(fn map ->
        [
          map.metric,
          map.internal_name,
          map.frequency_seconds,
          map.docs |> Enum.map(& &1.link),
          map.available_assets
        ]
      end)

    csv_content =
      [["Metric", "Internal Name", "Frequency", "Docs", "Available Assets"]] ++ csv_content

    csv_content
    |> NimbleCSV.RFC4180.dump_to_iodata()
  end
end
