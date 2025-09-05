defmodule SanbaseWeb.AdminUserAuth do
  use SanbaseWeb, :verified_routes

  import Plug.Conn
  import Phoenix.Controller

  alias Sanbase.Accounts

  def log_out_user(conn) do
    SanbaseWeb.Guardian.revoke_and_remove_jwt_tokens_from_conn_session(conn)

    conn
    |> renew_session()
    |> redirect(to: ~p"/admin")
  end

  defp renew_session(conn) do
    conn
    |> configure_session(renew: true)
    |> clear_session()
  end

  @doc """
  Authenticates the user by looking into the session
  and remember me token.
  """
  def assign_current_user_or_redirect(conn, _opts) do
    with token when token != nil <- get_session(conn, :refresh_token),
         {:ok, %Accounts.User{} = user, _claims} <- SanbaseWeb.Guardian.resource_from_token(token) do
      user = user |> Sanbase.Repo.preload([:roles, roles: :role])

      conn
      |> assign(:current_user, user)
    else
      _ ->
        conn
        |> put_flash(:error, "You must log in to access this page")
        |> maybe_store_return_to()
        |> redirect(to: ~p"/admin_auth/login")
        |> halt()
    end
  end

  def assign_current_user_roles(conn, _opts) do
    %Sanbase.Accounts.User{} = user = conn.assigns.current_user

    roles =
      user.roles
      |> Enum.sort_by(& &1.role.id, :desc)
      |> Enum.map(& &1.role.name)

    conn
    |> assign(:current_user_role_names, roles)
  end

  def ensure_user_has_admin_panel_role(conn, _opts) do
    has_admin_role? =
      Enum.any?(conn.assigns.current_user_role_names, &String.starts_with?(&1, "Admin Panel"))

    if has_admin_role? do
      conn
    else
      conn
      |> put_flash(:error, "You must have an Admin Panel role to access this page")
      |> halt()
      |> send_resp(401, """
      Unauthorized. You must have an Admin Panel role to access this page

      In order to gain a role, a Backend Team member (ivan.i or tsvetozar.p) should execute one of these:
      To give a Viewer role: Sanbase.Accounts.UserRole.create(#{conn.assigns.current_user.id}, #{Sanbase.Accounts.Role.admin_panel_viewer_role_id()})
      To give a Editor role: Sanbase.Accounts.UserRole.create(#{conn.assigns.current_user.id}, #{Sanbase.Accounts.Role.admin_panel_editor_role_id()})
      To give a Owner  role: Sanbase.Accounts.UserRole.create(#{conn.assigns.current_user.id}, #{Sanbase.Accounts.Role.admin_panel_owner_role_id()})
      """)
    end
  end

  def on_mount(:mount_current_user, _params, session, socket) do
    {:cont, mount_current_user(socket, session)}
  end

  def on_mount(:ensure_authenticated, _params, session, socket) do
    socket = mount_current_user(socket, session)

    if socket.assigns.current_user do
      {:cont, socket}
    else
      socket =
        socket
        |> Phoenix.LiveView.put_flash(:error, "You must log in to access this page.")
        |> Phoenix.LiveView.redirect(to: ~p"/admin_auth/login")

      {:halt, socket}
    end
  end

  def on_mount(:redirect_if_user_is_authenticated, _params, session, socket) do
    socket = mount_current_user(socket, session)

    if socket.assigns.current_user do
      {:halt,
       socket
       |> Phoenix.LiveView.put_flash(
         :info,
         "You are already authenticated as #{socket.assigns.current_user.email}."
       )
       |> Phoenix.LiveView.redirect(to: signed_in_path(socket))}
    else
      {:cont, socket}
    end
  end

  def on_mount(:extract_and_assign_current_user_roles, _params, session, socket) do
    socket =
      socket
      |> mount_current_user(session)
      |> Phoenix.Component.assign_new(:current_user_role_ids, fn ->
        socket.assigns.current_user.roles
        |> Enum.map(& &1.role.id)
      end)
      |> Phoenix.Component.assign_new(:current_user_role_names, fn ->
        socket.assigns.current_user.roles
        |> Enum.sort_by(& &1.role.id, :desc)
        |> Enum.map(& &1.role.name)
      end)

    {:cont, socket}
  end

  def on_mount(:ensure_user_has_metric_registry_role, _params, _session, socket) do
    roles = socket.assigns.current_user_role_names

    if Enum.any?(roles, &String.starts_with?(&1, "Metric Registry")) do
      {:cont, socket}
    else
      socket =
        socket
        |> Phoenix.LiveView.put_flash(
          :error,
          """
          You must have a Metric Registry role in order to access this page.

          To get a role:
          Viewer: Sanbase.Accounts.UserRole.create(#{socket.assigns.current_user.id}, #{Sanbase.Accounts.Role.metric_registry_viewer_role_id()})
          Owner: Sanbase.Accounts.UserRole.create(#{socket.assigns.current_user.id}, #{Sanbase.Accounts.Role.metric_registry_owner_role_id()})
          """
        )
        |> Phoenix.LiveView.redirect(to: ~p"/admin")

      {:halt, socket}
    end
  end

  defp mount_current_user(socket, session) do
    Phoenix.Component.assign_new(socket, :current_user, fn ->
      with %{"refresh_token" => token} <- session,
           {:ok, %Accounts.User{} = user, _claims} <-
             SanbaseWeb.Guardian.resource_from_token(token) do
        user
        |> Sanbase.Repo.preload([:roles, roles: :role])
      else
        _ ->
          nil
      end
    end)
  end

  @doc """
  Used for routes that require the user to not be authenticated.
  """
  def redirect_if_user_is_authenticated(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
      |> put_flash(:info, "You are already authenticated as #{conn.assigns.current_user.email}.")
      |> redirect(to: signed_in_path(conn))
      |> halt()
    else
      conn
    end
  end

  @doc """
  Used for routes that require the user to be authenticated.

  If you want to enforce the user email is confirmed before
  they use the application at all, here would be a good place.
  """
  def require_authenticated_user(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
    else
      conn
      |> put_flash(:error, "You must log in to access this page.")
      |> maybe_store_return_to()
      |> redirect(to: ~p"/admin_auth/login")
      |> halt()
    end
  end

  def require_authenticated_user2(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
    else
      conn
      |> put_flash(:error, "You must log in to access this page.")
      |> maybe_store_return_to()
      |> redirect(to: ~p"/admin_auth/login")
      |> halt()
    end
  end

  def tweets_prediction_authenticated_user(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
    else
      conn
      |> put_flash(:error, "You must log in to access this page.")
      |> maybe_store_return_to()
      |> redirect(to: ~p"/admin_auth/login")
      |> halt()
    end
  end

  defp maybe_store_return_to(%{method: "GET"} = conn) do
    put_session(conn, :user_return_to, current_path(conn))
  end

  defp maybe_store_return_to(conn), do: conn

  defp signed_in_path(_conn), do: ~p"/admin"
end
