defmodule SanbaseWeb.GenericAdminControllerTest do
  @moduledoc """
  The admin UI only renders the buttons a resource declares in its `:actions`
  and the caller's role allows. The routes stay reachable without those
  buttons, so these tests cover the server-side re-check on every mutating
  action.
  """
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory

  alias Sanbase.Model.Infrastructure

  # "infrastructures" declares actions: [:new, :edit] — no :delete
  @resource "infrastructures"

  defp sign_in(role_factory) do
    user = insert(:user)
    role = insert(role_factory)
    {:ok, _user_role} = Sanbase.Accounts.UserRole.create(user.id, role.id)
    {:ok, jwt_tokens} = SanbaseWeb.Guardian.get_jwt_tokens(user)

    Plug.Test.init_test_session(build_conn(), jwt_tokens)
  end

  test "an editor can open the new form of a resource that declares :new" do
    conn = get(sign_in(:role_admin_panel_editor), ~p"/admin/generic/new?resource=#{@resource}")

    assert html_response(conn, 200) =~ "code"
  end

  test "a viewer cannot create — the role has no :new permission" do
    conn =
      post(sign_in(:role_admin_panel_viewer), ~p"/admin/generic?resource=#{@resource}", %{
        "resource" => @resource,
        @resource => %{"code" => "SHOULD-NOT-EXIST"}
      })

    assert redirected_to(conn) == ~p"/admin/generic?resource=#{@resource}"
    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Not allowed to new"
    refute Sanbase.Repo.get_by(Infrastructure, code: "SHOULD-NOT-EXIST")
  end

  test "a viewer cannot open the edit form" do
    infrastructure = insert(:infrastructure)

    conn =
      get(
        sign_in(:role_admin_panel_viewer),
        ~p"/admin/generic/#{infrastructure.id}/edit?resource=#{@resource}"
      )

    assert redirected_to(conn) == ~p"/admin/generic?resource=#{@resource}"
    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Not allowed to edit"
  end

  test "even an owner cannot delete a resource that does not declare :delete" do
    infrastructure = insert(:infrastructure)

    conn =
      delete(
        sign_in(:role_admin_panel_owner),
        ~p"/admin/generic/#{infrastructure.id}?resource=#{@resource}"
      )

    assert redirected_to(conn) == ~p"/admin/generic?resource=#{@resource}"
    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Not allowed to delete"
    assert Sanbase.Repo.get(Infrastructure, infrastructure.id)
  end

  test "an unknown resource is refused rather than raising" do
    conn =
      delete(sign_in(:role_admin_panel_owner), ~p"/admin/generic/1?resource=no_such_resource")

    assert redirected_to(conn) == ~p"/admin/generic?resource=no_such_resource"
    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Not allowed to delete"
  end

  describe "show_action" do
    defp show_action_path(action, id),
      do: ~p"/admin/generic/show_action?#{[action: action, resource: "users", id: id]}"

    test "a viewer cannot run a mutating custom action" do
      target = insert(:user, is_mcp_banned: false)

      conn = get(sign_in(:role_admin_panel_viewer), show_action_path("mcp_ban_user", target.id))

      assert redirected_to(conn) == ~p"/admin/generic?resource=users"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Not allowed"
      refute Sanbase.Repo.get(Sanbase.Accounts.User, target.id).is_mcp_banned
    end

    test "an editor can run a mutating custom action" do
      target = insert(:user, is_mcp_banned: false)

      conn = get(sign_in(:role_admin_panel_editor), show_action_path("mcp_ban_user", target.id))

      assert html_response(conn, 200)
      assert Sanbase.Repo.get(Sanbase.Accounts.User, target.id).is_mcp_banned
    end

    test "a viewer can still run a read-only custom action" do
      target = insert(:user)

      conn =
        get(sign_in(:role_admin_panel_viewer), show_action_path("view_user_overview", target.id))

      assert redirected_to(conn) == "/admin/user_overview?user_id=#{target.id}"
    end

    test "an action the resource does not declare is refused, not dispatched" do
      target = insert(:user)

      # A real public function on the admin module, but not a declared show action.
      conn = get(sign_in(:role_admin_panel_owner), show_action_path("has_many", target.id))

      assert redirected_to(conn) == ~p"/admin/generic?resource=users"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Not allowed"
    end

    test "an action name that is not an existing atom is refused, not raised" do
      target = insert(:user)

      conn =
        get(sign_in(:role_admin_panel_owner), show_action_path("no_such_action_xyz", target.id))

      assert redirected_to(conn) == ~p"/admin/generic?resource=users"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Not allowed"
    end
  end
end
