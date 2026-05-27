defmodule Sanbase.MCP.SocialTrendsUI do
  @moduledoc """
  MCP App UI resource for the Social Trends tool.

  Fetches the bundled HTML from `MCP_APPS_BASE_URL/widgets/social-trends.html`
  (built by the `san-mcp-apps` repo with `PUBLIC_BASE_URL` so asset URLs are
  already absolute) and declares the deployment domain in `_meta.ui.csp` so the
  host's strict default CSP lets the iframe load scripts and styles from it.
  """

  use Anubis.Server.Component,
    type: :resource,
    uri: "ui://santiment/social-trends",
    name: "social-trends-ui",
    mime_type: "text/html;profile=mcp-app"

  alias Anubis.MCP.Error
  alias Anubis.Server.Response

  @impl true
  def read(_params, frame) do
    base_url = Application.fetch_env!(:sanbase, :mcp_apps_base_url)

    case Req.get(base_url <> "/widgets/social-trends.html", receive_timeout: 5_000) do
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
        {:error, Error.execution("Social Trends widget unavailable"), frame}
    end
  end
end
