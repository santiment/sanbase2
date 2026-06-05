defmodule Sanbase.MCP.ChartUI do
  @moduledoc """
  MCP App UI resource for the `show_chart` tool.

  Fetches the bundled widget HTML from `MCP_APPS_BASE_URL/widgets/chart.html`
  and declares the deployment domain in `_meta.ui.csp.resourceDomains` so the
  host's strict default CSP lets the sandboxed iframe load assets from it.
  """

  use Anubis.Server.Component,
    type: :resource,
    uri: "ui://santiment/chart",
    name: "chart-ui",
    mime_type: "text/html;profile=mcp-app"

  alias Anubis.MCP.Error
  alias Anubis.Server.Response

  @impl true
  def read(_params, frame) do
    base_url = Application.fetch_env!(:sanbase, :mcp_apps_base_url)

    case Req.get(base_url <> "/widgets/chart.html", receive_timeout: 5_000) do
      {:ok, %{status: 200, body: html}} ->
        meta = %{
          "ui" => %{
            "csp" => %{"resourceDomains" => [base_url]},
            "prefersBorder" => true
          }
        }

        response =
          Response.resource()
          |> Response.text(html)
          |> Map.update!(:metadata, &Map.put(&1, "_meta", meta))

        {:reply, response, frame}

      _ ->
        {:error, Error.execution("Chart widget unavailable"), frame}
    end
  end
end
