defmodule Sanbase.MCP.AuthPlug do
  @moduledoc """
  Plug that enforces authentication for MCP endpoints.
  Supports both OAuth Bearer tokens and API key authentication.
  Rejects unauthenticated requests with 401 before they reach the MCP server.
  """
  @behaviour Plug

  import Plug.Conn

  alias Boruta.Oauth.Authorization

  @doc "Returns the given options unchanged."
  @spec init(opts :: term()) :: term()
  @impl Plug
  def init(opts), do: opts

  @doc "Authenticates via OAuth Bearer token or API key and assigns the user to the conn."
  @spec call(conn :: Plug.Conn.t(), opts :: term()) :: Plug.Conn.t()
  @impl Plug
  def call(conn, _opts) do
    case get_authorization_value(conn) do
      nil ->
        reject(conn, "Authorization header required")

      header_value ->
        case try_oauth(header_value) || try_apikey(header_value) do
          {:ok, user} -> assign(conn, :current_user, user)
          nil -> reject(conn, "Invalid credentials")
        end
    end
  end

  defp get_authorization_value(conn) do
    case get_req_header(conn, "authorization") do
      [value | _] when byte_size(value) > 0 -> value
      _ -> nil
    end
  end

  defp try_oauth("Bearer " <> token) do
    if String.starts_with?(token, "Apikey ") do
      nil
    else
      with {:ok, oauth_token} <- Authorization.AccessToken.authorize(value: token),
           {:ok, user} <-
             Sanbase.Accounts.User.by_id(Sanbase.Math.to_integer(oauth_token.sub)) do
        {:ok, user}
      else
        _ -> nil
      end
    end
  end

  defp try_oauth(_), do: nil

  defp try_apikey(header_value) do
    case extract_apikey(header_value) do
      nil ->
        nil

      apikey ->
        case Sanbase.Accounts.Apikey.apikey_to_user(apikey) do
          {:ok, %Sanbase.Accounts.User{} = user} -> {:ok, user}
          _ -> nil
        end
    end
  end

  defp extract_apikey(header_value) do
    case header_value do
      "Bearer Apikey " <> apikey -> apikey
      "Apikey " <> apikey -> apikey
      "Bearer " <> apikey -> apikey
      _ -> nil
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
