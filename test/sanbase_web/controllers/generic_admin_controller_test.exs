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

  describe "feature_toggles" do
    setup do
      # The migration inserts this row. structure.sql has no data, so insert it here.
      toggle =
        Sanbase.Repo.insert!(%Sanbase.FeatureToggle{
          name: "user_registration",
          enabled: true
        })

      %{toggle: toggle}
    end

    defp update_toggle(conn, toggle, params) do
      put(conn, ~p"/admin/generic/#{toggle.id}?resource=feature_toggles", %{
        "resource" => "feature_toggles",
        "feature_toggles" => params
      })
    end

    test "the index page lists the toggles" do
      conn = get(sign_in(:role_admin_panel_viewer), ~p"/admin/generic?resource=feature_toggles")

      assert html_response(conn, 200) =~ "user_registration"
    end

    test "the admin home page sidebar links to the toggles" do
      html = sign_in(:role_admin_panel_viewer) |> get(~p"/admin") |> html_response(200)

      assert html =~ ~s(href="/admin/generic?resource=feature_toggles")
      assert html =~ "Feature Toggles"
    end

    test "an editor can disable and enable registration", %{toggle: toggle} do
      editor_conn = sign_in(:role_admin_panel_editor)

      conn = update_toggle(editor_conn, toggle, %{"enabled" => "false"})
      assert redirected_to(conn) =~ "/admin/generic"
      refute Sanbase.FeatureToggle.user_registration_enabled?()

      update_toggle(editor_conn, toggle, %{"enabled" => "true"})
      assert Sanbase.FeatureToggle.user_registration_enabled?()
    end

    test "turning the reduced Business allowance on and off from the admin panel", context do
      # The migration inserts this row; structure.sql has no data.
      toggle =
        Sanbase.Repo.get_by(Sanbase.FeatureToggle, name: "business_reduced_api_calls") ||
          Sanbase.Repo.insert!(%Sanbase.FeatureToggle{
            name: "business_reduced_api_calls",
            enabled: false
          })

      customer = insert(:user, email: "business-admin-toggle@example.com")
      editor_conn = sign_in(:role_admin_panel_editor)

      update_toggle(editor_conn, toggle, %{"enabled" => "true"})
      assert %DateTime{} = Sanbase.FeatureToggle.business_reduced_api_calls_since()

      # Subscribes after the toggle went on, so is on the reduced allowance.
      insert(:subscription_pro,
        user: customer,
        plan_id: context.plans.plan_business_pro_monthly.id,
        status: :active,
        stripe_id: "sub_" <> Ecto.UUID.generate(),
        inserted_at: NaiveDateTime.add(NaiveDateTime.utc_now(), 60)
      )

      {:ok, _} = Sanbase.ApiCallLimit.update_user_plan(customer)
      assert acl_month(customer) == 50_000

      conn = update_toggle(editor_conn, toggle, %{"enabled" => "false"})
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "successfully"
      assert Sanbase.FeatureToggle.business_reduced_api_calls_since() == nil

      # Turning it off refreshed the customer without any subscription event.
      assert acl_month(customer) == 600_000
    end

    defp acl_month(user) do
      Sanbase.ApiCallLimit
      |> Sanbase.Repo.get_by!(user_id: user.id)
      |> Sanbase.ApiCallLimit.acl_to_api_call_limits()
      |> Map.fetch!(:month)
    end

    test "the name cannot be changed from the admin panel", %{toggle: toggle} do
      update_toggle(sign_in(:role_admin_panel_editor), toggle, %{
        "enabled" => "false",
        "name" => "renamed"
      })

      assert Sanbase.Repo.get!(Sanbase.FeatureToggle, toggle.id).name == "user_registration"
    end

    test "a viewer cannot change a toggle", %{toggle: toggle} do
      conn = update_toggle(sign_in(:role_admin_panel_viewer), toggle, %{"enabled" => "false"})

      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Not allowed"
      assert Sanbase.FeatureToggle.user_registration_enabled?()
    end
  end
end
