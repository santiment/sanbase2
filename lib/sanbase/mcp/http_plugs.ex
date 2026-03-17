defmodule Sanbase.MCP.AuthPlug do
  @moduledoc """
  Plug that enforces OAuth Bearer token authentication for MCP endpoints.
  Rejects unauthenticated requests with 401 before they reach the MCP server.
  """
  @behaviour Plug

  import Plug.Conn

  alias Boruta.Oauth.Authorization

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    case get_bearer_token(conn) do
      nil ->
        reject(conn, "Bearer token required")

      bearer ->
        case Authorization.AccessToken.authorize(value: bearer) do
          {:ok, token} ->
            case Sanbase.Accounts.User.by_id(Sanbase.Math.to_integer(token.sub)) do
              {:ok, _user} -> conn
              _ -> reject(conn, "Invalid user")
            end

          _ ->
            reject(conn, "Invalid or expired token")
        end
    end
  end

  defp get_bearer_token(conn) do
    case get_req_header(conn, "authorization") do
      [value | _] ->
        case String.split(value, " ", parts: 2) do
          [scheme, token] when byte_size(token) > 0 ->
            if String.downcase(scheme) == "bearer", do: token, else: nil

          _ ->
            nil
        end

      _ ->
        nil
    end
  end

  defp reject(conn, description) do
    body = Jason.encode!(%{error: "unauthorized", error_description: description})

    conn
    |> put_resp_content_type("application/json")
    |> put_resp_header("www-authenticate", "Bearer")
    |> send_resp(401, body)
    |> halt()
  end
end

defmodule Sanbase.MCP.StreamableHTTPPlug do
  @moduledoc "Wrapper plug to expose Sanbase.MCP.Server via forward"
  @behaviour Plug

  import Plug.Conn, only: [get_req_header: 2, put_req_header: 3]

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    conn = normalize_post_accept_header(conn)

    Anubis.Server.Transport.StreamableHTTP.Plug.call(
      conn,
      Anubis.Server.Transport.StreamableHTTP.Plug.init(server: Sanbase.MCP.Server)
    )
  end

  # When both JSON and SSE are advertised on POST, Anubis can choose SSE
  # response mode and keep the response stream open, causing client timeouts.
  # Force JSON responses for POST requests; SSE remains available via GET.
  defp normalize_post_accept_header(%Plug.Conn{method: "POST"} = conn) do
    case get_req_header(conn, "accept") do
      [accept | _] ->
        if String.contains?(accept, "application/json") and
             String.contains?(accept, "text/event-stream") do
          put_req_header(conn, "accept", "application/json")
        else
          conn
        end

      _ ->
        conn
    end
  end

  defp normalize_post_accept_header(conn), do: conn
end

defmodule Sanbase.MCP.StreamableHTTPDevPlug do
  @moduledoc "Wrapper plug to expose Sanbase.MCP.DevServer via forward"
  @behaviour Plug

  import Plug.Conn, only: [get_req_header: 2, put_req_header: 3]

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    conn = normalize_post_accept_header(conn)

    Anubis.Server.Transport.StreamableHTTP.Plug.call(
      conn,
      Anubis.Server.Transport.StreamableHTTP.Plug.init(server: Sanbase.MCP.DevServer)
    )
  end

  defp normalize_post_accept_header(%Plug.Conn{method: "POST"} = conn) do
    case get_req_header(conn, "accept") do
      [accept | _] ->
        if String.contains?(accept, "application/json") and
             String.contains?(accept, "text/event-stream") do
          put_req_header(conn, "accept", "application/json")
        else
          conn
        end

      _ ->
        conn
    end
  end

  defp normalize_post_accept_header(conn), do: conn
end
