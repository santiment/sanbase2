defmodule Sanbase.MCP.SocialTrendsUI do
  @moduledoc """
  MCP App UI resource for the Social Trends tool.

  Serves the self-contained, single-file social-trends widget bundled into this
  app at `priv/mcp_widgets/social-trends.html` (built by the
  `santiment/san-mcp-apps` repo via `pnpm build:single`). See
  `Sanbase.MCP.WidgetAsset`.
  """

  use Anubis.Server.Component,
    type: :resource,
    uri: "ui://santiment/social-trends",
    name: "social-trends-ui",
    mime_type: "text/html;profile=mcp-app"

  @impl true
  def read(_params, frame), do: Sanbase.MCP.WidgetAsset.serve("social-trends.html", frame)
end
