defmodule Sanbase.MCP.Knowledge.AuthPlug do
  @moduledoc """
  Restricts `/mcp_knowledge` to team members, for every method. No or invalid
  credentials get a 401 that starts OAuth; non-team users get a 403.
  """
  @behaviour Plug

  import Plug.Conn

  alias Sanbase.MCP.Knowledge.Access

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    case Sanbase.MCP.Auth.headers_list_to_user(conn.req_headers) do
      nil ->
        reject(conn, 401, "unauthorized", "Valid credentials required")

      user ->
        if Access.allowed?(user) do
          assign(conn, :current_user, user)
        else
          reject(conn, 403, "forbidden", Access.denied_message())
        end
    end
  end

  defp reject(conn, status, error, description) do
    body = Jason.encode!(%{error: error, error_description: description})
    backend_url = Sanbase.Utils.Config.module_get(SanbaseWeb.Endpoint, :backend_url)
    resource_metadata_url = "#{backend_url}/.well-known/oauth-protected-resource/mcp_knowledge"

    conn
    |> put_resp_content_type("application/json")
    |> maybe_put_www_authenticate(status, resource_metadata_url)
    |> send_resp(status, body)
    |> halt()
  end

  defp maybe_put_www_authenticate(conn, 401, resource_metadata_url) do
    put_resp_header(
      conn,
      "www-authenticate",
      ~s(Bearer resource_metadata="#{resource_metadata_url}")
    )
  end

  defp maybe_put_www_authenticate(conn, _status, _url), do: conn
end
