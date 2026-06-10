defmodule Sanbase.MCP.ChartUI do
  @moduledoc """
  MCP App UI resource for the `show_chart` tool.

  Serves the self-contained, single-file chart widget bundled into this app at
  `priv/mcp_widgets/chart.html` (built by the `santiment/san-mcp-apps` repo via
  `pnpm build:single`). See `Sanbase.MCP.WidgetAsset`.
  """

  use Anubis.Server.Component,
    type: :resource,
    uri: "ui://santiment/chart",
    name: "chart-ui",
    mime_type: "text/html;profile=mcp-app"

  # Content-versioned URI (overrides the static one above) so hosts re-fetch
  # the widget whenever the bundled HTML changes. See WidgetAsset.ui_uri/2.
  def uri, do: Sanbase.MCP.WidgetAsset.ui_uri("chart", "chart.html")

  @impl true
  def read(_params, frame), do: Sanbase.MCP.WidgetAsset.serve("chart.html", frame)
end
