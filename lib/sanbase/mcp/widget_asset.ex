defmodule Sanbase.MCP.WidgetAsset do
  @moduledoc """
  Shared helper for MCP App UI resources.

  Serves a self-contained, single-file widget HTML bundled into
  `priv/mcp_widgets/` (built by the `santiment/san-mcp-apps` repo via
  `pnpm build:single`). All JS/CSS/fonts are inlined, so the MCP host's strict
  default CSP needs no extra domains and the widget works with just the Elixir
  server running — no external widget host.

  The widget HTML is a static build artifact: it is read from disk once and
  cached in `:persistent_term`, so subsequent renders serve it from memory.
  A fresh build is picked up on the next app restart.
  """

  alias Anubis.MCP.Error
  alias Anubis.Server.Frame
  alias Anubis.Server.Response

  @meta %{"ui" => %{"prefersBorder" => true}}

  @doc """
  Serves the widget `filename` from `priv/mcp_widgets/` as an MCP App UI
  resource response, e.g. `serve("chart.html", frame)`.

  Returns `{:reply, response, frame}` with the inlined HTML, or
  `{:error, error, frame}` if the file cannot be read.
  """
  @spec serve(filename :: String.t(), Frame.t()) ::
          {:reply, Response.t(), Frame.t()} | {:error, Error.t(), Frame.t()}
  def serve(filename, frame) do
    case load(filename) do
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

  defp load(filename) do
    key = {__MODULE__, filename}

    case :persistent_term.get(key, nil) do
      nil ->
        path = Application.app_dir(:sanbase, Path.join(["priv", "mcp_widgets", filename]))

        with {:ok, html} <- File.read(path) do
          :persistent_term.put(key, html)
          {:ok, html}
        end

      html ->
        {:ok, html}
    end
  end
end
