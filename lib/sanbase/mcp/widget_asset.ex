defmodule Sanbase.MCP.WidgetAsset do
  @moduledoc """
  Shared helper for MCP App UI resources.

  Serves a self-contained, single-file widget HTML bundled into
  `priv/mcp_widgets/` (built by the `santiment/san-mcp-apps` repo via
  `pnpm build:single`). All JS/CSS/fonts are inlined, so the MCP host's strict
  default CSP needs no extra domains and the widget works with just the Elixir
  server running — no external widget host.
  """

  alias Anubis.MCP.Error
  alias Anubis.Server.Frame
  alias Anubis.Server.Response

  @meta %{"ui" => %{"prefersBorder" => true}}

  @spec serve(filename :: String.t(), Frame.t()) ::
          {:reply, Response.t(), Frame.t()} | {:error, Error.t(), Frame.t()}
  def serve(filename, frame) do
    path = Application.app_dir(:sanbase, Path.join(["priv", "mcp_widgets", filename]))

    case File.read(path) do
      {:ok, html} ->
        response =
          Response.resource()
          |> Response.text(html)
          |> Map.update!(:metadata, &Map.put(&1, "_meta", @meta))

        {:reply, response, frame}

      {:error, reason} ->
        {:error, Error.execution("Widget #{filename} unavailable: #{inspect(reason)}"), frame}
    end
  end
end
