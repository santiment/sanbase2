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

  describe "assign_role" do
    test "an owner can assign a role" do
      # sign_in/1 already inserted the owner role at its fixed id.
      {_owner, conn} = sign_in(:role_admin_panel_owner)
      target = insert(:user, email: "target@santiment.net")

      {:ok, view, _html} = live(conn, "/admin/user_roles")

      render_change(view, "assign_role", %{
        "role_assignment" => %{"user_id" => "#{target.id}", "role_id" => "#{owner_role_id()}"}
      })

      assert has_role?(target.id, owner_role_id())
    end
  end

  describe "handle_event authorization" do
    # A non-owner's roles in assigns — the state a client that bypassed or
    # outlived the mount check would have.
    setup do
      socket = %Phoenix.LiveView.Socket{
        assigns: %{
          __changed__: %{},
          flash: %{},
          current_user_role_names: ["Admin Panel Viewer"],
          search_query: ""
        }
      }

      {:ok, socket: socket}
    end

    test "assign_role is refused for a non-owner", %{socket: socket} do
      target = insert(:user, email: "target2@santiment.net")
      role_id = owner_role_id()
      insert(:role_admin_panel_owner)

      {:noreply, socket} =
        SanbaseWeb.Admin.UserRolesLive.handle_event(
          "assign_role",
          %{"role_assignment" => %{"user_id" => "#{target.id}", "role_id" => "#{role_id}"}},
          socket
        )

      assert socket.assigns.flash["error"] =~ "Only an Admin Panel Owner"
      refute has_role?(target.id, role_id)
    end

    test "remove_role is refused for a non-owner", %{socket: socket} do
      target = insert(:user, email: "target3@santiment.net")
      role = insert(:role_admin_panel_owner)
      {:ok, _} = UserRole.create(target.id, role.id)

      {:noreply, socket} =
        SanbaseWeb.Admin.UserRolesLive.handle_event(
          "remove_role",
          %{"user_id" => "#{target.id}", "role_id" => "#{role.id}"},
          socket
        )

      assert socket.assigns.flash["error"] =~ "Only an Admin Panel Owner"
      assert has_role?(target.id, role.id)
    end
  end
end
