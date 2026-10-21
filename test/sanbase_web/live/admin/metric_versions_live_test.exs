defmodule SanbaseWeb.Admin.MetricVersionsLiveTest do
  use SanbaseWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Sanbase.MetricVersionAliasHelpers, only: [admin_conn: 1, create_alias!: 1]

  alias Sanbase.Metric.VersionAlias

  setup do
    VersionAlias.clear_cache()
    [conn: admin_conn(:role_admin_panel_editor)]
  end

  describe "the version list" do
    test "shows every version with the plans that can use it", %{conn: conn} do
      configured =
        create_alias!(%{
          version_num: "7.0",
          version_name: "seven:v1",
          plan_access: [%{product: "SANAPI", plan: "BUSINESS_PRO"}]
        })

      unconfigured = create_alias!(%{version_num: "7.1", version_name: "seven_pit:v1"})

      {:ok, view, _html} = live(conn, ~p"/admin/metric_versions")

      assert has_element?(view, "#metric-version-#{configured.id}", "Business Pro")
      refute has_element?(view, "#metric-version-#{configured.id}", "Needs plan access")
      assert has_element?(view, "#metric-version-#{unconfigured.id}", "Needs plan access")
    end

    test "creates a version without plan access", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/metric_versions")

      view |> element("#new-version-button") |> render_click()

      {:ok, _show, html} =
        view
        |> form("#new-version-form",
          version_alias: %{scope: "global", version_num: "7.0", version_name: "seven:v1"}
        )
        |> render_submit()
        |> follow_redirect(conn)

      assert html =~ "Created seven:v1"
      assert {:ok, "7.0"} == VersionAlias.to_version_num("seven:v1")
      assert %VersionAlias{plan_access: []} = VersionAlias.get("7.0")
    end

    test "shows validation errors on the form", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/metric_versions")

      view |> element("#new-version-button") |> render_click()

      html =
        view
        |> form("#new-version-form", version_alias: %{version_num: "7.0", version_name: "Seven"})
        |> render_submit()

      assert html =~ "must look like"
      assert VersionAlias.get("7.0") == nil
    end
  end

  describe "a version's page" do
    setup do
      [version: create_alias!(%{version_num: "7.0", version_name: "seven:v1"})]
    end

    test "saves the plans ticked in the grid", %{conn: conn, version: version} do
      {:ok, view, _html} = live(conn, ~p"/admin/metric_versions/#{version.id}")

      enable(view, "SANAPI", "BUSINESS_MAX")

      view
      |> form("#plan-access-form", %{
        "access" => %{
          "SANAPI" => %{
            "BUSINESS_MAX" => %{"billing_interval" => "year", "accessible_if_trial" => "false"}
          }
        }
      })
      |> render_change()

      enable(view, "SANBASE", "ANY")

      assert has_element?(view, "#unsaved-access")
      assert has_element?(view, "#access-summary-SANAPI", "Business Max (yearly, no trial)")

      view |> form("#plan-access-form") |> render_submit()

      assert %VersionAlias{plan_access: rows} = VersionAlias.get("7.0")

      assert rows
             |> Enum.map(&{&1.product, &1.plan, &1.billing_interval, &1.accessible_if_trial})
             |> Enum.sort() ==
               [{"SANAPI", "BUSINESS_MAX", "year", false}, {"SANBASE", "ANY", "any", true}]

      refute has_element?(view, "#unsaved-access")
    end

    test "unticking a plan takes its access away", %{conn: conn} do
      version =
        create_alias!(%{
          version_num: "8.0",
          version_name: "eight:v1",
          plan_access: [
            %{product: "SANAPI", plan: "PRO"},
            %{product: "SANAPI", plan: "BUSINESS_PRO"}
          ]
        })

      {:ok, view, _html} = live(conn, ~p"/admin/metric_versions/#{version.id}")

      view
      |> form("#plan-access-form", %{
        "access" => %{"SANAPI" => %{"PRO" => %{"enabled" => "false"}}}
      })
      |> render_change()

      view |> form("#plan-access-form") |> render_submit()

      assert %VersionAlias{plan_access: [%{plan: "BUSINESS_PRO"}]} = VersionAlias.get("8.0")
    end

    test "discarding brings back the saved plans", %{conn: conn, version: version} do
      {:ok, view, _html} = live(conn, ~p"/admin/metric_versions/#{version.id}")

      enable(view, "SANAPI", "PRO")
      assert has_element?(view, "#unsaved-access")

      view |> element("#discard-access") |> render_click()

      refute has_element?(view, "#unsaved-access")
      refute has_element?(view, "#access-SANAPI-PRO-enabled[checked]")
    end

    test "narrowing exposed_in removes the access of the other product", %{conn: conn} do
      version =
        create_alias!(%{
          version_num: "8.0",
          version_name: "eight:v1",
          plan_access: [%{product: "SANAPI", plan: "PRO"}, %{product: "SANBASE", plan: "ANY"}]
        })

      {:ok, view, _html} = live(conn, ~p"/admin/metric_versions/#{version.id}")

      view
      |> form("#version-details-form", version_alias: %{exposed_in: "api_only"})
      |> render_change()

      assert has_element?(view, "#exposure-removes-access", "Sanbase All plans")

      view
      |> form("#version-details-form", version_alias: %{exposed_in: "api_only"})
      |> render_submit()

      assert %VersionAlias{exposed_in: "api_only", plan_access: [%{product: "SANAPI"}]} =
               VersionAlias.get("8.0")

      assert has_element?(view, "#access-SANBASE", "Not exposed in Sanbase")
    end

    test "deletes the version", %{conn: conn, version: version} do
      {:ok, view, _html} = live(conn, ~p"/admin/metric_versions/#{version.id}")

      {:ok, _index, html} =
        view |> element("#delete-version") |> render_click() |> follow_redirect(conn)

      assert html =~ "Deleted seven:v1"
      assert {:error, _} = VersionAlias.to_version_num("seven:v1")
    end

    test "the default version is not configured by plan", %{conn: conn} do
      version = create_alias!(%{version_num: "1.0", version_name: "original:v1"})

      {:ok, view, _html} = live(conn, ~p"/admin/metric_versions/#{version.id}")

      assert render(view) =~ "Every plan can always use it"
      assert has_element?(view, "#access-SANAPI-PRO-enabled[disabled]")
      refute has_element?(view, "#save-access")
    end
  end

  describe "an Admin Panel Viewer" do
    test "sees the version but cannot change it" do
      conn = admin_conn(:role_admin_panel_viewer)
      version = create_alias!(%{version_num: "7.0", version_name: "seven:v1"})

      {:ok, index, _html} = live(conn, ~p"/admin/metric_versions")
      refute has_element?(index, "#new-version-button")

      {:ok, view, _html} = live(conn, ~p"/admin/metric_versions/#{version.id}")

      refute has_element?(view, "#save-access")
      refute has_element?(view, "#delete-version")
      assert has_element?(view, "#access-SANAPI-PRO-enabled[disabled]")

      assert render_hook(view, "save_access", %{}) =~ "Admin Panel Editor role"
      assert render_hook(view, "delete", %{}) =~ "Admin Panel Editor role"
      assert %VersionAlias{} = VersionAlias.get("7.0")
    end
  end

  defp enable(view, product, plan) do
    view
    |> form("#plan-access-form", %{"access" => %{product => %{plan => %{"enabled" => "true"}}}})
    |> render_change()
  end
end
