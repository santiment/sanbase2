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
