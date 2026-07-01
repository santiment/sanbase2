defmodule Mix.Tasks.Mcp.Widgets.Setup do
  @moduledoc """
  Installs npm dependencies for the MCP App widget bundles.

  Counterpart to `mix mcp.widgets.build` — split out so Docker can cache the
  install layer independently of widget source changes, mirroring the
  `assets.setup` / `assets.build` split used for esbuild/tailwind.

  Uses `pnpm install`. Idempotent on a pre-populated `node_modules/` (e.g. a
  Docker layer that already installed deps).

  pnpm is required (not npm) because `san-webkit-next` declares ~30 runtime
  `peerDependencies` (rxjs, bits-ui, indicatorts, …) without marking any as
  optional. pnpm's `auto-install-peers` resolves them transitively into its
  `.pnpm/` store; npm with `legacy-peer-deps` ignores them and the build
  fails to resolve `rxjs`.

      mix mcp.widgets.setup
  """

  use Mix.Task

  @shortdoc "Installs pnpm dependencies for MCP App widget bundles"

  @widgets_dir "assets/mcp_widgets"

  @impl Mix.Task
  def run(_args) do
    case System.cmd("pnpm", ["install"], cd: @widgets_dir, into: IO.stream(:stdio, :line)) do
      {_, 0} -> :ok
      {_, code} -> Mix.raise("pnpm install failed with exit code #{code}")
    end
  end
end
