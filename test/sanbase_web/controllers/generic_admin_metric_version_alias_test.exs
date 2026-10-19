defmodule SanbaseWeb.GenericAdminMetricVersionAliasTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.MetricVersionAliasHelpers, only: [admin_owner_conn: 0, create_alias!: 1]

  alias Sanbase.Metric.VersionAlias
  alias Sanbase.Metric.VersionPlanAccess

  @resource "metric_version_aliases"

  setup do
    VersionAlias.clear_cache()
    [conn: admin_owner_conn()]
  end

  test "creating an alias through the admin makes the name resolve at once", %{conn: conn} do
    assert {:error, _} = VersionAlias.to_version_num("seven:v1")

    conn =
      post(conn, ~p"/admin/generic?resource=#{@resource}", %{
        "resource" => @resource,
        @resource => %{
          "version_num" => "7.0",
          "version_name" => "seven:v1",
          "description" => ""
        }
      })

    assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "created successfully"
    assert {:ok, "7.0"} == VersionAlias.to_version_num("seven:v1")
  end

  test "deleting an alias through the admin stops the name resolving at once", %{conn: conn} do
    row = create_alias!(%{version_num: "7.0", version_name: "seven:v1"})

    assert {:ok, "7.0"} == VersionAlias.to_version_num("seven:v1")

    conn = delete(conn, ~p"/admin/generic/#{row.id}?resource=#{@resource}")

    assert redirected_to(conn) == ~p"/admin/generic?resource=#{@resource}"
    assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "deleted successfully"
    assert {:error, _} = VersionAlias.to_version_num("seven:v1")
  end

  test "a validation error is shown on the form instead of a constraint error", %{conn: conn} do
    conn =
      post(conn, ~p"/admin/generic?resource=#{@resource}", %{
        "resource" => @resource,
        @resource => %{
          "version_num" => "7.0",
          "version_name" => "Seven-PIT"
        }
      })

    assert html_response(conn, 200) =~ "must look like"
  end

  test "exposed_in is set through the admin and applies at once", %{conn: conn} do
    row = create_alias!(%{version_num: "7.0", version_name: "seven:v1"})

    conn =
      put(conn, ~p"/admin/generic/#{row.id}?resource=#{@resource}", %{
        "resource" => @resource,
        @resource => %{"exposed_in" => "api_only"}
      })

    assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "updated successfully"
    assert %VersionAlias{exposed_in: "api_only"} = VersionAlias.get("7.0")
  end

  describe "plan access" do
    @plan_access "metric_version_plan_access"

    test "is listed on the alias page", %{conn: conn} do
      row =
        create_alias!(%{
          version_num: "7.0",
          version_name: "seven:v1",
          plan_access: [%{product: "SANAPI", plan: "BUSINESS_PRO"}]
        })

      html = conn |> get(~p"/admin/generic/#{row.id}?resource=#{@resource}") |> html_response(200)

      assert html =~ "Plan access"
      assert html =~ "BUSINESS_PRO"

      new_form =
        conn
        |> get(
          ~p"/admin/generic/new?resource=#{@plan_access}&linked_resource=version_alias&linked_resource_id=#{row.id}"
        )
        |> html_response(200)

      assert new_form =~ "seven:v1 (7.0, global)"
    end

    test "created through the admin applies at once", %{conn: conn} do
      row = create_alias!(%{version_num: "7.0", version_name: "seven:v1"})
      assert %VersionAlias{plan_access: []} = VersionAlias.get("7.0")

      conn =
        post(conn, ~p"/admin/generic?resource=#{@plan_access}", %{
          "resource" => @plan_access,
          @plan_access => %{
            "version_alias_id" => "#{row.id}",
            "product" => "SANBASE",
            "plan" => "MAX",
            "billing_interval" => "any",
            "include_trial" => "true"
          }
        })

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "created successfully"

      assert %VersionAlias{plan_access: [%{product: "SANBASE", plan: "MAX"}]} =
               VersionAlias.get("7.0")
    end

    test "deleted through the admin is gone at once", %{conn: conn} do
      create_alias!(%{
        version_num: "7.0",
        version_name: "seven:v1",
        plan_access: [%{product: "SANBASE", plan: "MAX"}]
      })

      %VersionAlias{plan_access: [plan_access]} = VersionAlias.get("7.0")

      conn = delete(conn, ~p"/admin/generic/#{plan_access.id}?resource=#{@plan_access}")

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "deleted successfully"
      assert %VersionAlias{plan_access: []} = VersionAlias.get("7.0")
      assert Sanbase.Repo.get(VersionPlanAccess, plan_access.id) == nil
    end
  end
end
