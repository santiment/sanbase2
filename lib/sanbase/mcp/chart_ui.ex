defmodule Sanbase.MCP.ChartUI do
  @moduledoc """
  MCP App UI resource for the `show_chart` tool.

  Serves the self-contained, single-file chart widget bundled into this app at
  `priv/mcp_widgets/chart.html` (built from `assets/mcp_widgets/` via
  `mix mcp.widgets.build`). See `Sanbase.MCP.WidgetAsset`.
  """

  use Anubis.Server.Component,
    type: :resource,
    uri_template: "ui://santiment/chart-{version}",
    name: "chart-ui",
    mime_type: "text/html;profile=mcp-app"

  alias Sanbase.MCP.WidgetAsset

  @doc """
  Current content-versioned URI, advertised in the `show_chart` tool's
  `_meta.ui.resourceUri` so hosts re-fetch the widget whenever the bundled
  HTML changes. `read/2` accepts any version (or the bare base URI), so
  clients holding a stale tool list still get the current widget instead of
  a resource-not-found error.
  """
  def current_uri, do: WidgetAsset.ui_uri("chart", "chart.html")

  @impl true
  def read(%{"uri" => "ui://santiment/chart" <> _}, frame),
    do: WidgetAsset.serve("chart.html", frame)

  def read(%{"uri" => uri}, frame), do: WidgetAsset.not_found(uri, frame)
end
