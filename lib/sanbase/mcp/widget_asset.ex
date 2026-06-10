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
    case fetch(filename) do
      {:ok, {html, _version}} ->
        response =
          Response.resource()
          |> Response.text(html)
          |> Map.update!(:metadata, &Map.put(&1, "_meta", @meta))

        {:reply, response, frame}

      {:error, reason} ->
        {:error, Error.execution("Widget #{filename} unavailable: #{inspect(reason)}"), frame}
    end
  end

  @doc """
  Content-versioned `ui://` URI for a bundled widget, e.g.
  `ui_uri("chart", "chart.html")` -> `"ui://santiment/chart-1a2b3c4d"`.

  MCP hosts cache app resources by URI, so the version suffix is derived from
  the artifact's content hash — every widget rebuild automatically busts the
  host cache, with no manual version bumping. Use it both for the resource's
  `uri/0` and the tool's `_meta.ui.resourceUri` so they always agree.
  """
  @spec ui_uri(base :: String.t(), filename :: String.t()) :: String.t()
  def ui_uri(base, filename) do
    case fetch(filename) do
      {:ok, {_html, version}} -> "ui://santiment/#{base}-#{version}"
      {:error, _reason} -> "ui://santiment/#{base}"
    end
  end

  defp fetch(filename) do
    key = {__MODULE__, filename}

    case :persistent_term.get(key, nil) do
      nil ->
        path = Application.app_dir(:sanbase, Path.join(["priv", "mcp_widgets", filename]))

        with {:ok, html} <- File.read(path) do
          entry = {html, content_version(html)}
          if cache?(), do: :persistent_term.put(key, entry)
          {:ok, entry}
        end

      entry ->
        {:ok, entry}
    end
  end

  defp content_version(html) do
    :crypto.hash(:sha256, html)
    |> Base.encode16(case: :lower)
    |> binary_part(0, 8)
  end

  # In dev, skip the cache so a rebuilt widget is picked up without a restart.
  defp cache?, do: Application.get_env(:sanbase, :env) != :dev
end
