defmodule SanbaseWeb.Admin.MemoryStatsLiveTest do
  use SanbaseWeb.ConnCase, async: true

  @moduletag capture_log: true

  import Phoenix.LiveViewTest
  import Sanbase.Factory

  alias Sanbase.Monitoring.MemoryStat

  setup do
    user = insert(:user)
    admin_role = insert(:role_admin_panel_viewer)
    {:ok, _user_role} = Sanbase.Accounts.UserRole.create(user.id, admin_role.id)
    {:ok, jwt_tokens} = SanbaseWeb.Guardian.get_jwt_tokens(user)
    conn = Plug.Test.init_test_session(build_conn(), jwt_tokens)
    {:ok, conn: conn}
  end

  defp insert_stat(overrides) do
    attrs =
      Map.merge(
        %{
          pod_name: "sanbase-web-0",
          container_type: "web",
          beam_started_at: ~U[2026-07-22 10:00:00Z],
          rss_bytes: 1_500_000_000,
          vm_total_bytes: 1_200_000_000,
          vm_processes_bytes: 500_000_000,
          vm_binary_bytes: 200_000_000,
          vm_ets_bytes: 300_000_000,
          vm_code_bytes: 100_000_000,
          alloc_used_bytes: 1_100_000_000,
          alloc_allocated_bytes: 1_400_000_000,
          process_count: 5000,
          atom_count: 100_000,
          sample_duration_ms: 12,
          details: %{
            top_ets: [%{name: ":graphql_cache", memory_bytes: 50_000_000, rows: 1000, owner: "X"}],
            process_groups: [%{name: "Sanbase.BigProcess", count: 3, memory_bytes: 99_000_000}]
          }
        },
        overrides
      )

    {:ok, stat} = MemoryStat.store(attrs)
    stat
  end

  test "renders empty state when no pods reported", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/admin/memory_stats")

    assert html =~ "Memory Stats"
    assert html =~ "No pods reported recently"
  end

  test "lists live pods with their latest sample", %{conn: conn} do
    insert_stat(%{})
    insert_stat(%{pod_name: "sanbase-admin-x", container_type: "admin"})

    {:ok, _view, html} = live(conn, "/admin/memory_stats")

    assert html =~ "sanbase-web-0"
    assert html =~ "sanbase-admin-x"
    assert html =~ "1.12 GB"
  end

  test "selecting a pod shows latest sample, diff, details and samples", %{conn: conn} do
    insert_stat(%{vm_total_bytes: 1_000_000_000})
    insert_stat(%{vm_total_bytes: 1_200_000_000})

    {:ok, _view, html} = live(conn, "/admin/memory_stats?pod=sanbase-web-0")

    assert html =~ "sanbase-web-0 · latest sample"
    assert html =~ "Change over current incarnation"
    # details from the sample that has process groups
    assert html =~ ":graphql_cache"
    assert html =~ "Sanbase.BigProcess"
    assert html =~ "Recent samples"
  end

  test "selecting a pod that stopped reporting shows a warning", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/admin/memory_stats?pod=sanbase-gone-pod")

    assert html =~ "has not reported in the last"
  end
end
