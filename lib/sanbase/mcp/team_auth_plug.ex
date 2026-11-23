defmodule Sanbase.MCP.TeamAuthPlug do
  @moduledoc """
  Restricts a team-only MCP endpoint (`/mcp_knowledge`, `/mcp_dev`) to team members, for
  every method. No or invalid credentials get a 401 that starts OAuth; non-team users get
  a 403.

  Options:
    * `:resource_path` (required) - the endpoint path, e.g. `"/mcp_dev"`. The 401 points
      OAuth clients at `/.well-known/oauth-protected-resource<resource_path>`.
    * `:access` (required) - a module with `allowed?/1` and `denied_message/0`.
  """
  @behaviour Plug

  import Plug.Conn

  @impl Plug
  def init(opts) do
    %{
      resource_path: Keyword.fetch!(opts, :resource_path),
      access: Keyword.fetch!(opts, :access)
    }
  end

  @impl Plug
  def call(conn, %{access: access} = opts) do
    case Sanbase.MCP.Auth.headers_list_to_user(conn.req_headers) do
      nil ->
        reject(conn, opts, 401, "unauthorized", "Valid credentials required")

      user ->
        if access.allowed?(user) do
          assign(conn, :current_user, user)
        else
          reject(conn, opts, 403, "forbidden", access.denied_message())
        end
    end
  end

  defp reject(conn, opts, status, error, description) do
    body = Jason.encode!(%{error: error, error_description: description})

    conn
    |> put_resp_content_type("application/json")
    |> maybe_put_www_authenticate(status, opts.resource_path)
    |> send_resp(status, body)
    |> halt()
  end

  defp maybe_put_www_authenticate(conn, 401, resource_path) do
    backend_url = Sanbase.Utils.Config.module_get(SanbaseWeb.Endpoint, :backend_url)
    resource_metadata_url = "#{backend_url}/.well-known/oauth-protected-resource#{resource_path}"

    put_resp_header(
      conn,
      "www-authenticate",
      ~s(Bearer resource_metadata="#{resource_metadata_url}")
    )
  end

  defp maybe_put_www_authenticate(conn, _status, _resource_path), do: conn
end
