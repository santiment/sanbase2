defmodule SanbaseWeb.Admin.WritePagesViewerDeniedTest do
  @moduledoc """
  The Admin Panel Viewer role is read-only. The LiveViews that grant
  subscriptions, send notifications or start promo trials must redirect a Viewer
  away on mount, so none of their write events can be reached.
  """
  use SanbaseWeb.ConnCase, async: true

  @moduletag capture_log: true

  import Phoenix.LiveViewTest
  import Sanbase.Factory

  alias Sanbase.Accounts.UserRole

  @paths [
    "/admin/subscription_grants",
    "/admin/bundle_subscriptions",
    "/admin/notifications/broadcast",
    "/admin/notifications/manual/email",
    "/admin/promo_trials/new"
  ]

  defp sign_in(role_factory) do
    user = insert(:user, email: "admin#{System.unique_integer([:positive])}@santiment.net")
    role = insert(role_factory)
    {:ok, _} = UserRole.create(user.id, role.id)
    {:ok, jwt_tokens} = SanbaseWeb.Guardian.get_jwt_tokens(user)

    Plug.Test.init_test_session(build_conn(), jwt_tokens)
  end

  for path <- @paths do
    test "a viewer is redirected away from #{path}" do
      conn = sign_in(:role_admin_panel_viewer)

      assert {:error, {:redirect, %{to: "/admin"}}} = live(conn, unquote(path))
    end

    test "an editor can mount #{path}" do
      conn = sign_in(:role_admin_panel_editor)

      assert {:ok, _view, _html} = live(conn, unquote(path))
    end
  end
end
