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

  test "showing a record of an unknown resource returns 404 rather than raising" do
    conn = get(sign_in(:role_admin_panel_viewer), ~p"/admin/generic/1?resource=no_such_resource")

    assert html_response(conn, 404) =~ "Unknown resource."
  end

  test "the index page without a resource still asks for one" do
    conn = get(sign_in(:role_admin_panel_viewer), ~p"/admin/generic")

    assert html_response(conn, 200) =~ "You need to provide a resource!"
  end

  describe "show_action" do
    defp show_action_path(action, id),
      do: ~p"/admin/generic/show_action?#{[action: action, resource: "users", id: id]}"

    # Phoenix.ConnTest skips the CSRF check, but show_action re-enables it for POST,
    # so send a token like the show page form does.
    defp post_with_csrf(conn, path) do
      token = Plug.CSRFProtection.get_csrf_token()

      conn
      |> Plug.Test.init_test_session(%{"_csrf_token" => Plug.CSRFProtection.dump_state()})
      |> post(path, %{"_csrf_token" => token})
    end

    test "a viewer cannot run a mutating custom action" do
      target = insert(:user, is_mcp_banned: false)

      conn =
        post_with_csrf(
          sign_in(:role_admin_panel_viewer),
          show_action_path("mcp_ban_user", target.id)
        )

      assert redirected_to(conn) == ~p"/admin/generic?resource=users"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Not allowed"
      refute Sanbase.Repo.get(Sanbase.Accounts.User, target.id).is_mcp_banned
    end

    test "an editor can run a mutating custom action with POST" do
      target = insert(:user, is_mcp_banned: false)

      conn =
        post_with_csrf(
          sign_in(:role_admin_panel_editor),
          show_action_path("mcp_ban_user", target.id)
        )

      # post/redirect/get: back to the user page, so a refresh does not resubmit.
      assert redirected_to(conn) == "/admin/generic/#{target.id}?resource=users"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "banned from MCP"
      assert Sanbase.Repo.get(Sanbase.Accounts.User, target.id).is_mcp_banned
    end

    # SECURITY_ANALYSIS.md A2: a GET link to a mutating action is a CSRF vector —
    # the SameSite=Lax session cookie is sent on a cross-site link click and
    # `protect_from_forgery` does not check GET.
    for action <- ~w(reset_api_call_limits reset_queries_credits_spent mcp_ban_user
                     mcp_unban_user hide_activity_traces_user unhide_activity_traces_user) do
      @action action
      test "#{@action} is refused over GET, even for an owner" do
        target =
          insert(:user,
            is_mcp_banned: @action == "mcp_unban_user",
            are_activity_traces_hidden: false
          )

        before = Sanbase.Repo.get(Sanbase.Accounts.User, target.id)

        conn = get(sign_in(:role_admin_panel_owner), show_action_path(@action, target.id))

        assert redirected_to(conn) == "/admin/generic/#{target.id}?resource=users"
        assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "must be submitted with POST"

        after_get = Sanbase.Repo.get(Sanbase.Accounts.User, target.id)
        assert after_get.is_mcp_banned == before.is_mcp_banned
        assert after_get.are_activity_traces_hidden == before.are_activity_traces_hidden
      end
    end

    test "a mutating action runs on POST but not on GET" do
      target = insert(:user)
      parent = self()
      # One signed-in conn (the role factory has a fixed id, so sign in once).
      conn = sign_in(:role_admin_panel_owner)

      Sanbase.Mock.prepare_mock(Sanbase.ApiCallLimit, :reset, fn user ->
        send(parent, {:reset_called, user.id})
        :ok
      end)
      |> Sanbase.Mock.run_with_mocks(fn ->
        get(conn, show_action_path("reset_api_call_limits", target.id))
        refute_received {:reset_called, _}

        post_with_csrf(conn, show_action_path("reset_api_call_limits", target.id))
        assert_received {:reset_called, user_id}
        assert user_id == target.id
      end)
    end

    # The admin scope skips the CSRF check (SanbaseWeb.Plug.AdminPodOnly), but
    # show_action checks the token of a POST itself: SameSite=Lax blocks only
    # cross-site POSTs, not ones from a same-site origin.
    test "a mutating action is refused on POST without a valid CSRF token" do
      target = insert(:user, is_mcp_banned: false)
      conn = sign_in(:role_admin_panel_owner)

      assert_raise Plug.CSRFProtection.InvalidCSRFTokenError, fn ->
        post(conn, show_action_path("mcp_ban_user", target.id))
      end

      assert_raise Plug.CSRFProtection.InvalidCSRFTokenError, fn ->
        post(conn, show_action_path("mcp_ban_user", target.id), %{"_csrf_token" => "forged"})
      end

      refute Sanbase.Repo.get(Sanbase.Accounts.User, target.id).is_mcp_banned
    end

    # Cross-site POSTs are blocked by the browser: the session cookie is
    # SameSite=Lax, which is sent on a cross-site top-level GET but never on a
    # cross-site POST.
    test "the session cookie is SameSite=Lax and HttpOnly" do
      conn = get(sign_in(:role_admin_panel_owner), ~p"/admin/generic?resource=users")
      cookie_key = Sanbase.Utils.Config.module_get(SanbaseWeb.Plug.SessionPlug, :session_key)

      set_cookie =
        conn
        |> Plug.Conn.get_resp_header("set-cookie")
        |> Enum.find(&String.starts_with?(&1, cookie_key <> "="))

      assert set_cookie =~ ~r/SameSite=Lax/i
      assert set_cookie =~ ~r/HttpOnly/i

      # Locally the cookie is host-only, so the session works on localhost:4000
      # as well as on an /etc/hosts alias of the admin host.
      refute set_cookie =~ ~r/domain=/i
    end

    test "the session cookie has no Domain locally, whatever SANTIMENT_ROOT_DOMAIN says" do
      System.put_env("SANTIMENT_ROOT_DOMAIN", "sanbase-admin.stage.san")
      on_exit(fn -> System.delete_env("SANTIMENT_ROOT_DOMAIN") end)

      assert SanbaseWeb.Plug.SessionPlug.cookie_domain() == nil
    end

    test "the user page renders mutating actions as POST forms and read-only ones as links" do
      target = insert(:user)

      html =
        get(sign_in(:role_admin_panel_owner), ~p"/admin/generic/#{target.id}?resource=users")
        |> html_response(200)

      document = LazyHTML.from_document(html)

      form = LazyHTML.query(document, "form#show-action-mcp_ban_user")
      assert LazyHTML.attribute(form, "method") == ["post"]

      assert [_token] =
               LazyHTML.query(form, "input[name=_csrf_token]") |> LazyHTML.attribute("value")

      refute LazyHTML.query(document, "a[href*='action=mcp_ban_user']") |> Enum.any?()

      assert LazyHTML.query(document, "a[href*='action=view_user_overview']") |> Enum.any?()
    end

    test "a viewer can still run a read-only custom action" do
      target = insert(:user)

      conn =
        get(sign_in(:role_admin_panel_viewer), show_action_path("view_user_overview", target.id))

      assert redirected_to(conn) == "/admin/user_overview?user_id=#{target.id}"
    end

    test "a viewer can open the user's metrics usage page" do
      target = insert(:user)

      conn =
        get(
          sign_in(:role_admin_panel_viewer),
          show_action_path("view_user_metrics_usage", target.id)
        )

      assert redirected_to(conn) == "/admin/user_metrics_usage?user_id=#{target.id}"
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

  describe "user_apikey_tokens" do
    setup do
      user = insert(:user)
      {:ok, apikey} = Sanbase.Accounts.Apikey.generate_apikey(user)
      [token] = Sanbase.Repo.all(Sanbase.Accounts.UserApikeyToken)

      %{user: user, apikey: apikey, token: token}
    end

    test "the show page of a token renders", %{token: token, user: user} do
      conn =
        get(
          sign_in(:role_admin_panel_viewer),
          ~p"/admin/generic/#{token.id}?resource=user_apikey_tokens"
        )

      html = html_response(conn, 200)
      assert html =~ token.token
      assert html =~ user.email
    end

    test "an editor's delete revokes the apikey and keeps the row", ctx do
      assert {:ok, _} = Sanbase.Accounts.Apikey.apikey_to_user(ctx.apikey)

      conn =
        delete(
          sign_in(:role_admin_panel_editor),
          ~p"/admin/generic/#{ctx.token.id}?resource=user_apikey_tokens"
        )

      assert redirected_to(conn) == ~p"/admin/generic?resource=user_apikey_tokens"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "deleted successfully"
      token = Sanbase.Repo.get(Sanbase.Accounts.UserApikeyToken, ctx.token.id)
      assert %DateTime{} = token.revoked_at
      assert {:error, _} = Sanbase.Accounts.Apikey.apikey_to_user(ctx.apikey)
    end

    test "a viewer cannot delete a token", %{token: token, apikey: apikey} do
      conn =
        delete(
          sign_in(:role_admin_panel_viewer),
          ~p"/admin/generic/#{token.id}?resource=user_apikey_tokens"
        )

      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Not allowed to delete"
      assert Sanbase.Repo.get(Sanbase.Accounts.UserApikeyToken, token.id)
      assert {:ok, _} = Sanbase.Accounts.Apikey.apikey_to_user(apikey)
    end
  end

  describe "search" do
    setup do
      project = insert(:random_project)
      contract = insert(:contract_address, project: project)

      %{project: project, contract: contract}
    end

    defp search(conn, field, value) do
      get(conn, ~p"/admin/generic/search", %{
        "resource" => "contract_addresses",
        "search" => %{"filters" => %{"0" => %{"field" => field, "value" => value}}}
      })
    end

    test "a value that cannot be cast to the field type finds nothing", %{contract: contract} do
      conn = search(sign_in(:role_admin_panel_viewer), "project_id", "not-a-number")

      refute html_response(conn, 200) =~ contract.address
    end

    test "a non-numeric id finds nothing", %{contract: contract} do
      conn = search(sign_in(:role_admin_panel_viewer), "id", "not-a-number")

      refute html_response(conn, 200) =~ contract.address
    end

    test "a valid id finds the row", %{contract: contract} do
      conn = search(sign_in(:role_admin_panel_viewer), "id", to_string(contract.id))

      assert html_response(conn, 200) =~ contract.address
    end

    test "a valid value still finds the row", %{project: project, contract: contract} do
      conn = search(sign_in(:role_admin_panel_viewer), "project_id", to_string(project.id))

      assert html_response(conn, 200) =~ contract.address
    end
  end
end
