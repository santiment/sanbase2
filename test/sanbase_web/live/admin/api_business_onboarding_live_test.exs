defmodule SanbaseWeb.Admin.ApiBusinessOnboardingLiveTest do
  use SanbaseWeb.ConnCase

  import Phoenix.LiveViewTest
  import Sanbase.Factory
  import Mox

  alias Sanbase.Email.MockMailjetApi

  setup :set_mox_global
  setup :verify_on_exit!

  setup do
    user = insert(:user)
    admin_role = insert(:role_admin_panel_viewer)
    Sanbase.Accounts.UserRole.create(user.id, admin_role.id)
    {:ok, jwt_tokens} = SanbaseWeb.Guardian.get_jwt_tokens(user)
    conn = Plug.Test.init_test_session(build_conn(), jwt_tokens)
    {:ok, conn: conn}
  end

  test "renders the onboarding list contacts", %{conn: conn} do
    stub(MockMailjetApi, :fetch_list_emails, fn :api_business_onboarding ->
      {:ok, ["b@example.com", "a@example.com"]}
    end)

    {:ok, view, _html} = live(conn, "/admin/api_business_onboarding")
    html = render_async(view)

    assert html =~ "a@example.com"
    assert html =~ "b@example.com"
    assert html =~ "2 contacts"
  end

  test "shows a friendly message when the list is not configured", %{conn: conn} do
    stub(MockMailjetApi, :fetch_list_emails, fn :api_business_onboarding ->
      {:error, :list_not_configured}
    end)

    {:ok, view, _html} = live(conn, "/admin/api_business_onboarding")
    html = render_async(view)

    assert html =~ "not configured for this environment"
  end
end
