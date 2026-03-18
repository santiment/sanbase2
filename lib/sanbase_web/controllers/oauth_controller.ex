defmodule SanbaseWeb.OAuthController do
  @behaviour Boruta.Oauth.AuthorizeApplication
  @behaviour Boruta.Oauth.TokenApplication
  @behaviour Boruta.Openid.DynamicRegistrationApplication

  use SanbaseWeb, :controller

  require Logger

  alias Boruta.Oauth.AuthorizeResponse
  alias Boruta.Oauth.Error
  alias Boruta.Oauth.ResourceOwner
  alias Boruta.Oauth.TokenResponse
  alias Sanbase.Utils.Config

  # --- Metadata ---

  def metadata(conn, _params) do
    Logger.info("[OAuth] metadata discovery hit")
    backend_url = Config.module_get(SanbaseWeb.Endpoint, :backend_url)

    metadata = %{
      issuer: backend_url,
      authorization_endpoint: "#{backend_url}/oauth/authorize",
      token_endpoint: "#{backend_url}/oauth/token",
      registration_endpoint: "#{backend_url}/oauth/register",
      response_types_supported: ["code"],
      grant_types_supported: ["authorization_code", "refresh_token"],
      scopes_supported: ["openid", "profile", "email", "offline_access", "read", "write", "mcp"],
      code_challenge_methods_supported: ["S256"],
      token_endpoint_auth_methods_supported: ["none", "client_secret_post", "client_secret_basic"]
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
    Logger.info("[OAuth] authorize — all params: #{inspect(conn.params)}")

    case current_user_from_session(conn) do
      {:ok, user} ->
        # If we arrived here after login redirect (no OAuth params), but the
        # session has the original full URL, redirect to it to restore params.
        case {conn.params["client_id"], get_session(conn, :user_return_to)} do
          {nil, return_to} when is_binary(return_to) ->
            conn
            |> delete_session(:user_return_to)
            |> redirect(to: return_to)

          _ ->
            resource_owner = %ResourceOwner{sub: to_string(user.id), username: user.email}
            Boruta.Oauth.preauthorize(conn, resource_owner, __MODULE__)
        end

      :error ->
        conn = store_oauth_return_to(conn)
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
    Logger.info(
      "[OAuth] token — grant_type: #{inspect(conn.params["grant_type"])}, client_id: #{inspect(conn.params["client_id"])}"
    )

    conn = put_cors_headers(conn)
    Boruta.Oauth.token(conn, __MODULE__)
  end

  # --- Dynamic Client Registration (RFC 7591) ---

  def register(%Plug.Conn{} = conn, params) do
    Logger.info("[OAuth] register — all params: #{inspect(params)}")

    registration_params =
      %{
        redirect_uris: params["redirect_uris"] || [],
        supported_grant_types: params["grant_types"] || ["authorization_code"],
        pkce: true,
        public_refresh_token: true,
        confidential: false,
        access_token_ttl: 3600,
        authorization_code_ttl: 60,
        refresh_token_ttl: 30 * 86_400
      }
      |> maybe_put(:client_name, params["client_name"])
      |> maybe_put_auth_method(params["token_endpoint_auth_method"])

    conn = put_cors_headers(conn)
    Boruta.Openid.register_client(conn, registration_params, __MODULE__)
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
    Logger.warning(
      "[OAuth] authorize_error (redirect) — error: #{inspect(error.error)}, desc: #{inspect(error.error_description)}"
    )

    redirect(conn, external: Error.redirect_to_url(error))
  end

  def authorize_error(conn, %Error{
        status: status,
        error: error,
        error_description: error_description
      }) do
    Logger.warning(
      "[OAuth] authorize_error (json) — status: #{inspect(status)}, error: #{inspect(error)}, desc: #{inspect(error_description)}"
    )

    conn
    |> put_status(status)
    |> json(%{error: error, error_description: error_description})
  end

  @impl Boruta.Oauth.AuthorizeApplication
  def preauthorize_success(conn, response) do
    {:ok, user} = current_user_from_session(conn)

    conn
    |> put_resp_header("x-frame-options", "DENY")
    |> put_resp_content_type("text/html")
    |> send_resp(200, consent_html(user, conn, response))
  end

  @impl Boruta.Oauth.AuthorizeApplication
  def preauthorize_error(conn, %Error{status: :unauthorized, error: :invalid_resource_owner}) do
    redirect_to_login(conn)
  end

  def preauthorize_error(conn, %Error{format: format} = error) when not is_nil(format) do
    Logger.warning(
      "[OAuth] preauthorize_error (redirect) — error: #{inspect(error.error)}, desc: #{inspect(error.error_description)}"
    )

    redirect(conn, external: Error.redirect_to_url(error))
  end

  def preauthorize_error(conn, %Error{
        status: status,
        error: error,
        error_description: error_description
      }) do
    Logger.warning(
      "[OAuth] preauthorize_error (json) — status: #{inspect(status)}, error: #{inspect(error)}, desc: #{inspect(error_description)}"
    )

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
    Logger.warning(
      "[OAuth] token_error — status: #{inspect(status)}, error: #{inspect(error)}, desc: #{inspect(error_description)}"
    )

    conn
    |> put_status(status)
    |> json(%{error: error, error_description: error_description})
  end

  # --- Boruta DynamicRegistrationApplication callbacks ---

  @impl Boruta.Openid.DynamicRegistrationApplication
  def client_registered(conn, client) do
    Logger.info(
      "[OAuth] client_registered — id: #{client.id}, name: #{inspect(client.name)}, redirect_uris: #{inspect(client.redirect_uris)}"
    )

    response = %{
      client_id: client.id,
      client_secret: client.secret,
      client_name: client.name,
      redirect_uris: client.redirect_uris,
      grant_types: client.supported_grant_types,
      response_types: ["code"],
      token_endpoint_auth_method:
        List.first(client.token_endpoint_auth_methods || ["client_secret_post"])
    }

    conn
    |> put_status(201)
    |> json(response)
  end

  @impl Boruta.Openid.DynamicRegistrationApplication
  def registration_failure(conn, changeset) do
    Logger.warning("[OAuth] registration_failure — #{inspect(changeset.errors)}")

    errors =
      Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
        Enum.reduce(opts, msg, fn {key, value}, acc ->
          String.replace(acc, "%{#{key}}", to_string(value))
        end)
      end)

    conn
    |> put_status(400)
    |> json(%{error: "invalid_client_metadata", error_description: inspect(errors)})
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
    case Application.get_env(:sanbase, :env) do
      :prod ->
        backend_url = Config.module_get(SanbaseWeb.Endpoint, :backend_url)
        frontend_url = Config.module_get(SanbaseWeb.Endpoint, :frontend_url)

        # Pass only the short base path as `from` — the full OAuth query string
        # is already stored in the session (:user_return_to) and will be restored
        # when the user returns after login. This avoids very long URLs that get
        # mangled by Cloudflare challenges.
        login_url =
          "#{frontend_url}/login?from=#{URI.encode_www_form("#{backend_url}/oauth/authorize")}"

        redirect(conn, external: login_url)

      _ ->
        redirect(conn, to: "/oauth/dev_login")
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

  defp consent_html(user, conn, response) do
    user_display = Sanbase.Accounts.User.get_name(user)
    client_name = response.client.name || conn.params["client_id"] || "Unknown"
    csrf_token = Plug.CSRFProtection.get_csrf_token()
    query_string = conn.query_string

    """
    <!DOCTYPE html>
    <html>
    <head><title>Authorize MCP Access</title>
    <style>
      body { font-family: system-ui, -apple-system, sans-serif; max-width: 480px; margin: 0 auto; padding: 0 20px; color: #2f354a; display: flex; flex-direction: column; align-items: center; justify-content: center; min-height: 100vh; }
      h1 { font-size: 1.5em; font-weight: 700; margin-bottom: 8px; text-align: center; }
      p { color: #9faac4; line-height: 1.5; text-align: center; }
      .card { background: #fff; padding: 24px; border-radius: 8px; margin: 24px 0; border: 1px solid #e7eaf3; width: 100%; }
      .card dt { font-weight: 500; font-size: 0.75em; color: #9faac4; text-transform: uppercase; letter-spacing: 0.5px; margin-top: 16px; }
      .card dt:first-child { margin-top: 0; }
      .card dd { margin: 4px 0 0 0; font-size: 1.05em; color: #2f354a; }
      .actions { display: flex; gap: 12px; margin-top: 28px; width: 100%; }
      button { padding: 12px 32px; border-radius: 8px; border: 1px solid #e7eaf3; cursor: pointer; font-size: 1em; font-weight: 500; transition: all 0.15s; }
      .approve { background: #14c393; color: white; border-color: #14c393; }
      .approve:hover { background: #10a87e; }
      .deny { background: white; color: #2f354a; }
      .deny:hover { background: #f4f6fa; }
    </style>
    </head>
    <body>
      <h1>Authorize Application</h1>
      <p>An application is requesting access to your Santiment account.</p>
      <dl class="card">
        <dt>Signed in as</dt><dd>#{Phoenix.HTML.html_escape(user_display) |> Phoenix.HTML.safe_to_string()}</dd>
        <dt>Client</dt><dd>#{Phoenix.HTML.html_escape(client_name) |> Phoenix.HTML.safe_to_string()}</dd>
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

  # RFC 7591 allows "none" for public clients, but Boruta doesn't recognise it.
  # Since we already set confidential: false + pkce: true, just drop "none".
  defp maybe_put_auth_method(map, "none"), do: map
  defp maybe_put_auth_method(map, nil), do: map
  defp maybe_put_auth_method(map, method), do: Map.put(map, :token_endpoint_auth_method, method)

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
