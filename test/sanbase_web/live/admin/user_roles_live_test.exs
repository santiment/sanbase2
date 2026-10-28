defmodule SanbaseWeb.Admin.UserRolesLiveTest do
  @moduledoc """
  Assigning a role hands out privilege, so it is Owner-only — otherwise any
  "Admin Panel *" role, including the read-only Viewer, could grant itself Owner.
  """
  use SanbaseWeb.ConnCase, async: true

  @moduletag capture_log: true

  import Phoenix.LiveViewTest
  import Sanbase.Factory

  alias Sanbase.Accounts.UserRole

  defp sign_in(role_factory) do
    user = insert(:user, email: "admin#{System.unique_integer([:positive])}@santiment.net")
    role = insert(role_factory)
    {:ok, _user_role} = UserRole.create(user.id, role.id)
    {:ok, jwt_tokens} = SanbaseWeb.Guardian.get_jwt_tokens(user)

    {user, Plug.Test.init_test_session(build_conn(), jwt_tokens)}
  end

  defp owner_role_id(), do: Sanbase.Accounts.Role.admin_panel_owner_role_id()

  defp has_role?(user_id, role_id) do
    Sanbase.Repo.get_by(UserRole, user_id: user_id, role_id: role_id) != nil
  end

  describe "mount" do
    test "an owner can open the page" do
      {_user, conn} = sign_in(:role_admin_panel_owner)

      assert {:ok, _view, html} = live(conn, "/admin/user_roles")
      assert html =~ "User Roles Management"
    end

    for role <- [:role_admin_panel_viewer, :role_admin_panel_editor] do
      test "a #{role} is redirected away from the page" do
        {_user, conn} = sign_in(unquote(role))

        assert {:error, {:redirect, %{to: "/admin"}}} = live(conn, "/admin/user_roles")
      end
    end
  end

  describe "roles editor" do
    setup do
      {owner, conn} = sign_in(:role_admin_panel_owner)
      team_role = insert(:role_san_team)
      family_role = insert(:role_san_family)
      target = insert(:user, email: "target#{System.unique_integer([:positive])}@santiment.net")
      {:ok, _} = UserRole.create(target.id, team_role.id)

      %{owner: owner, conn: conn, target: target, team_role: team_role, family_role: family_role}
    end

    test "selecting a user shows their roles checked", ctx do
      {:ok, view, _html} = live(ctx.conn, "/admin/user_roles")

      view |> element("#edit-roles-#{ctx.target.id}") |> render_click()

      assert has_element?(view, "#roles-editor")
      assert has_element?(view, "#role-#{ctx.team_role.id}[checked]")
      refute has_element?(view, "#role-#{ctx.family_role.id}[checked]")
    end

    test "saving grants checked and revokes unchecked roles", ctx do
      {:ok, view, _html} = live(ctx.conn, "/admin/user_roles?user_id=#{ctx.target.id}")

      view
      |> form("#user-roles-form", %{
        roles: %{"#{ctx.team_role.id}" => "false", "#{ctx.family_role.id}" => "true"}
      })
      |> render_submit()

      assert has_role?(ctx.target.id, ctx.family_role.id)
      refute has_role?(ctx.target.id, ctx.team_role.id)
      assert has_element?(view, "#role-#{ctx.family_role.id}[checked]")
    end

    test "a non-santiment user cannot be granted roles", ctx do
      outsider = insert(:user, email: "outsider@example.com")
      {:ok, _} = UserRole.create(outsider.id, ctx.team_role.id)

      {:ok, view, _html} = live(ctx.conn, "/admin/user_roles?user_id=#{outsider.id}")

      assert has_element?(view, "#role-#{ctx.family_role.id}[disabled]")

      render_submit(view, "save_roles", %{"roles" => %{"#{ctx.family_role.id}" => "true"}})

      refute has_role?(outsider.id, ctx.family_role.id)
      assert has_role?(outsider.id, ctx.team_role.id)
    end

    test "an owner cannot revoke their own Owner role", ctx do
      {:ok, view, _html} = live(ctx.conn, "/admin/user_roles?user_id=#{ctx.owner.id}")

      render_submit(view, "save_roles", %{"roles" => %{"#{owner_role_id()}" => "false"}})

      assert has_role?(ctx.owner.id, owner_role_id())
    end
  end

  describe "handle_event authorization" do
    test "save_roles is refused for a non-owner" do
      target = insert(:user, email: "target2@santiment.net")
      insert(:role_admin_panel_owner)

      # A non-owner's roles in assigns — the state a client that bypassed or
      # outlived the mount check would have.
      socket = %Phoenix.LiveView.Socket{
        assigns: %{
          __changed__: %{},
          flash: %{},
          current_user_role_names: ["Admin Panel Viewer"],
          selected_user: target
        }
      }

      {:noreply, socket} =
        SanbaseWeb.Admin.UserRolesLive.handle_event(
          "save_roles",
          %{"roles" => %{"#{owner_role_id()}" => "true"}},
          socket
        )

      assert socket.assigns.flash["error"] =~ "Only an Admin Panel Owner"
      refute has_role?(target.id, owner_role_id())
    end
  end
end
