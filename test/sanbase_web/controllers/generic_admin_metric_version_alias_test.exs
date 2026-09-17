defmodule SanbaseWeb.GenericAdminMetricVersionAliasTest do
  @moduledoc """
  The alias resource keeps an in-memory copy of its rows. Every admin write,
  deletes included, must drop that copy so the next API request already sees
  the new mapping.
  """
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.MetricVersionAliasHelpers, only: [admin_owner_conn: 0, create_alias!: 1]

  alias Sanbase.Metric.VersionAlias

  @resource "metric_version_aliases"
  @metric "daily_active_addresses"

  setup do
    VersionAlias.clear_cache()
    [conn: admin_owner_conn()]
  end

  test "creating an alias through the admin makes the name resolve at once", %{conn: conn} do
    # Warm the cache with the current (empty) rows.
    assert {:error, _} = VersionAlias.to_version_num(@metric, "seven:v1")

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
    assert {:ok, "7.0"} == VersionAlias.to_version_num(@metric, "seven:v1")
  end

  test "deleting an alias through the admin stops the name resolving at once", %{conn: conn} do
    row = create_alias!(%{version_num: "7.0", version_name: "seven:v1"})

    assert {:ok, "7.0"} == VersionAlias.to_version_num(@metric, "seven:v1")

    conn = delete(conn, ~p"/admin/generic/#{row.id}?resource=#{@resource}")

    assert redirected_to(conn) == ~p"/admin/generic?resource=#{@resource}"
    assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "deleted successfully"
    assert {:error, _} = VersionAlias.to_version_num(@metric, "seven:v1")
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
end
