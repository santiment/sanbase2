defmodule Sanbase.MCP.TeamAuthPlug do
  @moduledoc """
  Restricts a team-only MCP endpoint (`/mcp_knowledge`, `/mcp_dev`) to team members, for
  every method. No or invalid credentials get a 401 that starts OAuth; non-team users get
  a 403.

  Options:
    * `:resource_path` (required) - the endpoint path, e.g. `"/mcp_dev"`. The 401 points
      OAuth clients at `/.well-known/oauth-protected-resource<resource_path>`.
    * `:access` (required) - a module with `allowed?/1` and `denied_message/0`.
    * `:scope` (required) - OAuth scope required on bearer tokens (e.g. `"mcp:dev"`),
      preventing tokens issued for `/mcp` from being replayed on team-only endpoints.
  """
  @behaviour Plug

  import Plug.Conn

  @banned_message "Your account is banned from the Santiment MCP server. Contact support."

  @impl Plug
  def init(opts) do
    %{
      resource_path: Keyword.fetch!(opts, :resource_path),
      access: Keyword.fetch!(opts, :access),
      scope: Keyword.fetch!(opts, :scope)
    }
  end

  @impl Plug
  def call(conn, %{access: access, scope: scope} = opts) do
    case Sanbase.MCP.Auth.headers_list_to_user(conn.req_headers, required_scope: scope) do
      nil ->
        reject(conn, opts, 401, "unauthorized", "Valid credentials required")

      %{is_mcp_banned: true} ->
        reject(conn, opts, 403, "forbidden", @banned_message)

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
    |> maybe_put_www_authenticate(status, opts)
    |> send_resp(status, body)
    |> halt()
  end

  defp maybe_put_www_authenticate(conn, 401, %{resource_path: resource_path, scope: scope}) do
    backend_url = Sanbase.Utils.Config.module_get(SanbaseWeb.Endpoint, :backend_url)
    resource_metadata_url = "#{backend_url}/.well-known/oauth-protected-resource#{resource_path}"

    put_resp_header(
      conn,
      "www-authenticate",
      ~s(Bearer resource_metadata="#{resource_metadata_url}", scope="#{scope}")
    )
  end

  defp maybe_put_www_authenticate(conn, _status, _opts), do: conn
end
