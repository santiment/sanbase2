defmodule SanbaseWeb.OAuthController do
  @behaviour Boruta.Oauth.AuthorizeApplication
  @behaviour Boruta.Oauth.TokenApplication

  use SanbaseWeb, :controller

  alias Boruta.Oauth.AuthorizeResponse
  alias Boruta.Oauth.Error
  alias Boruta.Oauth.ResourceOwner
  alias Boruta.Oauth.TokenResponse
  alias Sanbase.Utils.Config

  # --- Metadata ---

  def metadata(conn, _params) do
    backend_url = Config.module_get(SanbaseWeb.Endpoint, :backend_url)

    metadata = %{
      issuer: backend_url,
      authorization_endpoint: "#{backend_url}/oauth/authorize",
      token_endpoint: "#{backend_url}/oauth/token",
      response_types_supported: ["code"],
      grant_types_supported: ["authorization_code", "refresh_token"],
      code_challenge_methods_supported: ["S256"],
      token_endpoint_auth_methods_supported: ["client_secret_post", "client_secret_basic"]
    }

    conn |> put_cors_headers() |> json(metadata)
  end

  def protected_resource(conn, _params) do
    backend_url = Config.module_get(SanbaseWeb.Endpoint, :backend_url)

    resource = %{
      resource: "#{backend_url}/mcp",
      authorization_servers: ["#{backend_url}"]
    }

    conn |> put_cors_headers() |> json(resource)
  end

  def preflight(conn, _params) do
    conn
    |> put_cors_headers()
    |> send_resp(204, "")
  end

  # --- Authorize (GET) - preauthorize then show consent ---

  def authorize(%Plug.Conn{} = conn, _params) do
    conn = store_oauth_return_to(conn)

    case current_user_from_session(conn) do
      {:ok, user} ->
        resource_owner = %ResourceOwner{sub: to_string(user.id), username: user.email}
        Boruta.Oauth.preauthorize(conn, resource_owner, __MODULE__)

      :error ->
        redirect_to_login(conn)
    end
  end

  # --- Authorize Consent (POST) - user approved, issue the code ---

  def authorize_consent(%Plug.Conn{} = conn, %{"decision" => "approve"}) do
    case current_user_from_session(conn) do
      {:ok, user} ->
        resource_owner = %ResourceOwner{sub: to_string(user.id), username: user.email}
        Boruta.Oauth.authorize(conn, resource_owner, __MODULE__)

      :error ->
        redirect_to_login(conn)
    end
  end

  def authorize_consent(%Plug.Conn{} = conn, %{"decision" => "deny"} = params) do
    with redirect_uri when is_binary(redirect_uri) <- params["redirect_uri"],
         client_id when is_binary(client_id) <- params["client_id"],
         %Boruta.Ecto.Client{redirect_uris: uris} <-
           Sanbase.Repo.get(Boruta.Ecto.Client, client_id),
         true <- redirect_uri in uris do
      error_params = %{
        "error" => "access_denied",
        "error_description" => "The user denied the request"
      }

      error_params =
        case params["state"] do
          state when is_binary(state) and state != "" -> Map.put(error_params, "state", state)
          _ -> error_params
        end

      redirect_url = redirect_uri <> "?" <> URI.encode_query(error_params)
      redirect(conn, external: redirect_url)
    else
      _ ->
        request_path = get_session(conn, :user_return_to) || "/oauth/authorize"

        conn
        |> put_resp_header("x-frame-options", "DENY")
        |> put_status(403)
        |> put_resp_content_type("text/html")
        |> send_resp(403, denied_html(request_path))
    end
  end

  # --- Token ---

  def token(%Plug.Conn{} = conn, _params) do
    conn = put_cors_headers(conn)
    Boruta.Oauth.token(conn, __MODULE__)
  end

  # --- Boruta AuthorizeApplication callbacks ---

  @impl Boruta.Oauth.AuthorizeApplication
  def authorize_success(conn, %AuthorizeResponse{} = response) do
    redirect(conn, external: AuthorizeResponse.redirect_to_url(response))
  end

  @impl Boruta.Oauth.AuthorizeApplication
  def authorize_error(conn, %Error{status: :unauthorized, error: :invalid_resource_owner}) do
    redirect_to_login(conn)
  end

  def authorize_error(conn, %Error{format: format} = error) when not is_nil(format) do
    redirect(conn, external: Error.redirect_to_url(error))
  end

  def authorize_error(conn, %Error{
        status: status,
        error: error,
        error_description: error_description
      }) do
    conn
    |> put_status(status)
    |> json(%{error: error, error_description: error_description})
  end

  @impl Boruta.Oauth.AuthorizeApplication
  def preauthorize_success(conn, _response) do
    {:ok, user} = current_user_from_session(conn)

    conn
    |> put_resp_header("x-frame-options", "DENY")
    |> put_resp_content_type("text/html")
    |> send_resp(200, consent_html(user, conn))
  end

  @impl Boruta.Oauth.AuthorizeApplication
  def preauthorize_error(conn, %Error{status: :unauthorized, error: :invalid_resource_owner}) do
    redirect_to_login(conn)
  end

  def preauthorize_error(conn, %Error{format: format} = error) when not is_nil(format) do
    redirect(conn, external: Error.redirect_to_url(error))
  end

  def preauthorize_error(conn, %Error{
        status: status,
        error: error,
        error_description: error_description
      }) do
    conn
    |> put_status(status)
    |> json(%{error: error, error_description: error_description})
  end

  # --- Boruta TokenApplication callbacks ---

  @impl Boruta.Oauth.TokenApplication
  def token_success(conn, %TokenResponse{} = response) do
    body = %{
      access_token: response.access_token,
      token_type: response.token_type,
      expires_in: response.expires_in,
      refresh_token: response.refresh_token
    }

    conn
    |> put_resp_header("pragma", "no-cache")
    |> put_resp_header("cache-control", "no-store")
    |> json(body)
  end

  @impl Boruta.Oauth.TokenApplication
  def token_error(conn, %Error{status: status, error: error, error_description: error_description}) do
    conn
    |> put_status(status)
    |> json(%{error: error, error_description: error_description})
  end

  # --- Private ---

  defp current_user_from_session(conn) do
    access_token = get_session(conn, :access_token)

    case access_token && SanbaseWeb.Guardian.resource_from_token(access_token) do
      {:ok, %Sanbase.Accounts.User{} = user, _claims} -> {:ok, user}
      _ -> :error
    end
  end

  defp redirect_to_login(conn) do
    backend_url = Config.module_get(SanbaseWeb.Endpoint, :backend_url)
    resume_url = request_path_with_query(conn)

    case Application.get_env(:sanbase, :env) do
      :prod ->
        frontend_url = Config.module_get(SanbaseWeb.Endpoint, :frontend_url)

        login_url =
          "#{frontend_url}/login?from=#{URI.encode_www_form("#{backend_url}#{resume_url}")}"

        redirect(conn, external: login_url)

      _ ->
        redirect(conn, to: "/oauth/dev_login?return_to=#{URI.encode_www_form(resume_url)}")
    end
  end

  defp store_oauth_return_to(conn) do
    put_session(conn, :user_return_to, request_path_with_query(conn))
  end

  defp put_cors_headers(conn) do
    conn
    |> put_resp_header("access-control-allow-origin", "*")
    |> put_resp_header("access-control-allow-methods", "GET, POST, OPTIONS")
    |> put_resp_header("access-control-allow-headers", "content-type, authorization")
  end

  defp request_path_with_query(conn) do
    query = if conn.query_string != "", do: "?#{conn.query_string}", else: ""
    "#{conn.request_path}#{query}"
  end

  defp consent_html(user, conn) do
    user_display = Sanbase.Accounts.User.get_name(user)
    client_id = conn.params["client_id"] || "Unknown"
    scope = conn.params["scope"] || "default"
    csrf_token = Plug.CSRFProtection.get_csrf_token()
    query_string = conn.query_string

    """
    <!DOCTYPE html>
    <html>
    <head><title>Authorize MCP Access</title>
    <style>
      body { font-family: system-ui, -apple-system, sans-serif; max-width: 480px; margin: 80px auto; padding: 0 20px; color: #1a1a1a; }
      h1 { font-size: 1.4em; margin-bottom: 8px; }
      p { color: #555; line-height: 1.5; }
      .card { background: #f8f9fa; padding: 20px; border-radius: 10px; margin: 24px 0; border: 1px solid #e9ecef; }
      .card dt { font-weight: 600; font-size: 0.85em; color: #888; text-transform: uppercase; letter-spacing: 0.5px; margin-top: 12px; }
      .card dt:first-child { margin-top: 0; }
      .card dd { margin: 4px 0 0 0; font-size: 1.05em; }
      .actions { display: flex; gap: 12px; margin-top: 28px; }
      button { padding: 11px 28px; border-radius: 8px; border: 1px solid #d1d5db; cursor: pointer; font-size: 1em; font-weight: 500; transition: all 0.15s; }
      .approve { background: #2563eb; color: white; border-color: #2563eb; }
      .approve:hover { background: #1d4ed8; }
      .deny { background: white; color: #374151; }
      .deny:hover { background: #f3f4f6; }
    </style>
    </head>
    <body>
      <h1>Authorize Application</h1>
      <p>An application is requesting access to your Santiment account.</p>
      <dl class="card">
        <dt>Signed in as</dt><dd>#{Phoenix.HTML.html_escape(user_display) |> Phoenix.HTML.safe_to_string()}</dd>
        <dt>Client</dt><dd>#{Phoenix.HTML.html_escape(client_id) |> Phoenix.HTML.safe_to_string()}</dd>
        <dt>Scope</dt><dd>#{Phoenix.HTML.html_escape(scope) |> Phoenix.HTML.safe_to_string()}</dd>
      </dl>
      <form method="post" action="/oauth/authorize?#{Phoenix.HTML.html_escape(query_string) |> Phoenix.HTML.safe_to_string()}">
        <input type="hidden" name="_csrf_token" value="#{csrf_token}" />
        <div class="actions">
          <button type="submit" name="decision" value="approve" class="approve">Approve</button>
          <button type="submit" name="decision" value="deny" class="deny">Deny</button>
        </div>
      </form>
    </body>
    </html>
    """
  end

  defp denied_html(retry_path) do
    """
    <!DOCTYPE html>
    <html>
    <head><title>Access Denied</title>
    <style>
      body { font-family: system-ui, sans-serif; max-width: 480px; margin: 80px auto; padding: 0 20px; text-align: center; }
      h1 { font-size: 1.4em; }
      a { color: #2563eb; text-decoration: none; }
    </style>
    </head>
    <body>
      <h1>Access Denied</h1>
      <p>You denied the application access to your account.</p>
      <p><a href="#{Phoenix.HTML.html_escape(retry_path) |> Phoenix.HTML.safe_to_string()}">Try again</a></p>
    </body>
    </html>
    """
  end
end
