defmodule Mix.Tasks.Mcp.Widgets.Build do
  @moduledoc """
  Builds the MCP App widget bundles (`chart`, `social-trends`) into
  `priv/mcp_widgets/<name>.html` as single-file, self-contained HTML.

  Sources live under `assets/mcp_widgets/` (Svelte + Vite + `vite-plugin-singlefile`).
  Output HTML inlines all JS/CSS/fonts so the MCP host's strict default CSP
  needs no extra domains — `Sanbase.MCP.WidgetAsset` reads the files verbatim
  from disk and serves them as `text/html;profile=mcp-app` resources.

  Assumes `mix mcp.widgets.setup` has already installed the npm dependencies.

      mix mcp.widgets.build
  """

  use Mix.Task

  @shortdoc "Builds MCP App widget bundles into priv/mcp_widgets/"

  @widgets_dir "assets/mcp_widgets"

  @impl Mix.Task
  def run(_args) do
    case System.cmd("pnpm", ["run", "build"], cd: @widgets_dir, into: IO.stream(:stdio, :line)) do
      {_, 0} -> :ok
      {_, code} -> Mix.raise("pnpm run build failed with exit code #{code}")
    end
  end
end
