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
      metrics_map
      |> Sanbase.AvailableMetrics.apply_filters(filter)
      |> Sanbase.AvailableMetrics.sort_by_taxonomy()

    csv_content =
      metrics
      |> Enum.map(fn map ->
        categories = map.categories || []

        [
          map.metric,
          map.internal_name,
          categories
          |> Enum.map(& &1.category_name)
          |> Enum.reject(&is_nil/1)
          |> Enum.uniq()
          |> Enum.join(", "),
          categories
          |> Enum.map(& &1.group_name)
          |> Enum.reject(&is_nil/1)
          |> Enum.uniq()
          |> Enum.join(", "),
          map.frequency_seconds,
          map.docs |> Enum.map(& &1.link),
          map.available_assets
        ]
      end)

    csv_content =
      [
        [
          "Metric",
          "Internal Name",
          "Category",
          "Group",
          "Frequency",
          "Docs",
          "Available Assets"
        ]
      ] ++ csv_content

    csv_content
    |> NimbleCSV.RFC4180.dump_to_iodata()
  end
end
