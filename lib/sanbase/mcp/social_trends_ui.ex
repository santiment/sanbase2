defmodule Sanbase.MCP.SocialTrendsUI do
  @moduledoc """
  MCP App UI resource for the Social Trends tool.

  Serves the self-contained, single-file social-trends widget bundled into this
  app at `priv/mcp_widgets/social-trends.html` (built from `assets/mcp_widgets/`
  via `mix mcp.widgets.build`). See `Sanbase.MCP.WidgetAsset`.
  """

  use Anubis.Server.Component,
    type: :resource,
    uri_template: "ui://santiment/social-trends-{version}",
    name: "social-trends-ui",
    mime_type: "text/html;profile=mcp-app"

  alias Sanbase.MCP.WidgetAsset

  @doc """
  Current content-versioned URI, advertised in the tool's
  `_meta.ui.resourceUri`. `read/2` accepts any version (or the bare base
  URI) — see `Sanbase.MCP.ChartUI` for the rationale.
  """
  def current_uri, do: WidgetAsset.ui_uri("social-trends", "social-trends.html")

  @impl true
  def read(%{"uri" => "ui://santiment/social-trends" <> _}, frame),
    do: WidgetAsset.serve("social-trends.html", frame)

  def read(%{"uri" => uri}, frame), do: WidgetAsset.not_found(uri, frame)
end
