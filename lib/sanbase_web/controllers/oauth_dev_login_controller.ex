defmodule SanbaseWeb.OAuthDevLoginController do
  @moduledoc """
  Dev-only login screen for testing the OAuth flow locally.
  In production, users are redirected to the React app login instead.
  """
  use SanbaseWeb, :controller

  def show(conn, params) do
    return_to = params["return_to"] || "/oauth/authorize"

    conn
    |> put_resp_content_type("text/html")
    |> send_resp(200, dev_login_html(return_to))
  end

  def submit(conn, %{"email" => email, "return_to" => return_to}) do
    case Sanbase.Accounts.User.by_email(email) do
      {:ok, user} ->
        device_data = SanbaseWeb.Guardian.device_data(conn)

        case SanbaseWeb.Guardian.get_jwt_tokens(user, device_data) do
          {:ok, jwt_tokens_map} ->
            conn
            |> SanbaseWeb.Guardian.add_jwt_tokens_to_conn_session(jwt_tokens_map)
            |> redirect(to: safe_return_to(return_to))

          _ ->
            conn
            |> put_resp_content_type("text/html")
            |> send_resp(500, "Failed to create session")
        end

      _ ->
        conn
        |> put_resp_content_type("text/html")
        |> send_resp(400, dev_login_html(return_to, "User not found for email: #{email}"))
    end
  end

  defp dev_login_html(return_to, error \\ nil) do
    escaped_return_to = Plug.HTML.html_escape(return_to)

    error_html =
      if error,
        do: ~s(<p style="color:red">#{Plug.HTML.html_escape(error)}</p>),
        else: ""

    """
    <!DOCTYPE html>
    <html>
    <head><title>Dev Login - OAuth Flow</title>
    <style>
      body { font-family: system-ui, sans-serif; max-width: 400px; margin: 80px auto; padding: 0 20px; }
      input { display: block; width: 100%; padding: 8px; margin: 8px 0; border: 1px solid #ccc; border-radius: 4px; box-sizing: border-box; }
      button { padding: 10px 24px; background: #2563eb; color: white; border: none; border-radius: 6px; cursor: pointer; font-size: 1em; }
      .warning { background: #fef3c7; padding: 12px; border-radius: 6px; margin-bottom: 16px; font-size: 0.9em; }
    </style>
    </head>
    <body>
      <h1>Dev Login</h1>
      <div class="warning">This page is only available in development mode.</div>
      #{error_html}
      <form method="post" action="/oauth/dev_login">
        <input type="hidden" name="_csrf_token" value="#{Plug.CSRFProtection.get_csrf_token()}" />
        <input type="hidden" name="return_to" value="#{escaped_return_to}" />
        <label>Email of existing user:</label>
        <input type="email" name="email" placeholder="user@example.com" required />
        <button type="submit">Sign In</button>
      </form>
    </body>
    </html>
    """
  end

  defp safe_return_to(url) when is_binary(url) do
    if String.starts_with?(url, "/") and not String.starts_with?(url, "//") do
      url
    else
      "/oauth/authorize"
    end
  end

  defp safe_return_to(_), do: "/oauth/authorize"
end
