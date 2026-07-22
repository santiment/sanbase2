defmodule SanbaseWeb.Admin.MemoryStatsLiveTest do
  use SanbaseWeb.ConnCase, async: true

  @moduletag capture_log: true

  import Phoenix.LiveViewTest
  import Sanbase.Factory
  import Ecto.Query, only: [from: 2]

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
          rss_hwm_bytes: 2_500_000_000,
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

  test "selecting a pod shows latest sample, details and samples", %{conn: conn} do
    insert_stat(%{vm_total_bytes: 1_000_000_000})
    insert_stat(%{vm_total_bytes: 1_200_000_000})

    {:ok, _view, html} = live(conn, "/admin/memory_stats?pod=sanbase-web-0")

    assert html =~ "sanbase-web-0 · latest sample"
    # too few samples for the smoothed window stats
    refute html =~ "Window stats"
    # details from the sample that has process groups
    assert html =~ ":graphql_cache"
    assert html =~ "Sanbase.BigProcess"
    assert html =~ "Recent samples"
  end

  test "window stats show min/avg/max and a smoothed trend", %{conn: conn} do
    # 10 low samples then 10 high ones: trend = avg(last 5) - avg(first 5)
    for _ <- 1..10, do: insert_stat(%{vm_total_bytes: 1_000_000_000})
    for _ <- 1..10, do: insert_stat(%{vm_total_bytes: 2_000_000_000})

    {:ok, _view, html} = live(conn, "/admin/memory_stats?pod=sanbase-web-0")

    assert html =~ "Window stats, current incarnation"
    assert html =~ "Trend"
    # derived components computed per sample
    assert html =~ "Carrier slack (allocated − used)"
    assert html =~ "Native/other (RSS − allocated)"
    assert html =~ "RSS high-water"
    # min 1e9 bytes = 953.7 MB, max 2e9 = 1.86 GB (GiB-based),
    # trend = last-5 avg minus first-5 avg = +1e9
    assert html =~ "953.7 MB"
    assert html =~ "1.86 GB"
    assert html =~ "+953.7 MB"
  end

  test "selecting a pod with no recorded samples shows only a warning", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/admin/memory_stats?pod=sanbase-gone-pod")

    assert html =~ "No samples recorded for pod sanbase-gone-pod"
    refute html =~ "latest sample"
  end

  test "a stale pod shows the warning AND its recorded history", %{conn: conn} do
    stat = insert_stat(%{pod_name: "sanbase-old-deploy"})

    stale_time = NaiveDateTime.utc_now() |> NaiveDateTime.add(-1800, :second)

    Sanbase.Repo.update_all(
      from(s in MemoryStat, where: s.id == ^stat.id),
      set: [inserted_at: stale_time]
    )

    {:ok, view, html} = live(conn, "/admin/memory_stats?pod=sanbase-old-deploy")

    assert html =~ "has not reported in the last"
    assert html =~ "showing its recorded history"
    # data sections still render
    assert html =~ "sanbase-old-deploy · latest sample"
    assert html =~ ":graphql_cache"
    assert html =~ "Recent samples"

    assert_push_event(view, "chart-data-pod-chart", %{series: [%{name: "OS RSS"} | _]})
  end

  test "renders charts and pushes series data to the hooks", %{conn: conn} do
    insert_stat(%{rss_bytes: 100})
    insert_stat(%{pod_name: "sanbase-web-1", rss_bytes: 200})

    {:ok, view, html} = live(conn, "/admin/memory_stats?pod=sanbase-web-0")

    assert html =~ ~s(id="overview-chart")
    assert html =~ ~s(id="pod-chart")
    assert html =~ ~s(phx-hook="TimeseriesChart")

    assert_push_event(view, "chart-data-overview-chart", %{
      series: [%{name: "sanbase-web-0"}, %{name: "sanbase-web-1"}],
      value_kind: "bytes"
    })

    assert_push_event(view, "chart-data-pod-chart", %{series: [%{name: "OS RSS"} | _]})
  end

  test "default chart metric falls back to VM total when no pod reports RSS", %{conn: conn} do
    insert_stat(%{rss_bytes: nil})

    {:ok, view, html} = live(conn, "/admin/memory_stats")

    assert html =~ "VM total · all live pods"

    assert_push_event(view, "chart-data-overview-chart", %{
      series: [%{name: "sanbase-web-0", points: [[_, 1_200_000_000]]}],
      value_kind: "bytes"
    })
  end

  test "pod chart mode switches between buckets, layers and alloc util", %{conn: conn} do
    insert_stat(%{})

    {:ok, view, html} = live(conn, "/admin/memory_stats?pod=sanbase-web-0")

    assert html =~ "Buckets"

    assert_push_event(view, "chart-data-pod-chart", %{
      series: [%{name: "OS RSS"} | _],
      value_kind: "bytes"
    })

    html = render_click(view, "pod-chart-mode", %{"mode" => "layers"})

    assert html =~ "Layers (leak vs ratchet)"
    assert html =~ "carrier slack"

    assert_push_event(view, "chart-data-pod-chart", %{
      series: [%{name: "RSS high-water"} | _],
      value_kind: "bytes"
    })

    render_click(view, "pod-chart-mode", %{"mode" => "util"})

    assert_push_event(view, "chart-data-pod-chart", %{
      series: [%{name: "Allocator utilization", points: [[_, 78.6]]}],
      value_kind: "percent"
    })
  end

  test "chart-ready handshake re-pushes chart data", %{conn: conn} do
    insert_stat(%{})

    {:ok, view, _html} = live(conn, "/admin/memory_stats?pod=sanbase-web-0")

    # consume the initial pushes, then the handshake must push again
    assert_push_event(view, "chart-data-overview-chart", %{})
    assert_push_event(view, "chart-data-pod-chart", %{})

    render_hook(view, "chart-ready", %{"id" => "overview-chart"})

    assert_push_event(view, "chart-data-overview-chart", %{series: [%{name: "sanbase-web-0"}]})
    assert_push_event(view, "chart-data-pod-chart", %{series: [%{name: "OS RSS"} | _]})
  end

  test "metric badges toggle and combine byte metrics", %{conn: conn} do
    insert_stat(%{rss_bytes: 100, vm_total_bytes: 200})

    {:ok, view, _html} = live(conn, "/admin/memory_stats")

    # default: OS RSS alone, series named by pod
    assert_push_event(view, "chart-data-overview-chart", %{
      series: [%{name: "sanbase-web-0", points: [[_, 100]]}],
      value_kind: "bytes"
    })

    # toggle VM total on: both byte metrics, series named "pod · metric"
    html = render_click(view, "toggle-metric", %{"metric" => "vm_total_bytes"})

    assert html =~ "OS RSS + VM total · all live pods"

    assert_push_event(view, "chart-data-overview-chart", %{
      series: [
        %{name: "sanbase-web-0 · OS RSS", points: [[_, 100]]},
        %{name: "sanbase-web-0 · VM total", points: [[_, 200]]}
      ],
      value_kind: "bytes"
    })

    # toggling the last remaining metric off is a no-op
    render_click(view, "toggle-metric", %{"metric" => "vm_total_bytes"})
    html = render_click(view, "toggle-metric", %{"metric" => "rss_bytes"})
    assert html =~ "OS RSS · all live pods"
  end

  test "process count badge is exclusive and window badges switch", %{conn: conn} do
    insert_stat(%{process_count: 4321})

    {:ok, view, _html} = live(conn, "/admin/memory_stats")

    render_click(view, "toggle-metric", %{"metric" => "vm_total_bytes"})
    html = render_click(view, "toggle-metric", %{"metric" => "process_count"})

    # counts cannot share the bytes axis — selecting it drops the others
    assert html =~ "Process count · all live pods"

    html = render_click(view, "chart-window", %{"hours" => "6"})
    assert html =~ "last 6h"

    assert_push_event(view, "chart-data-overview-chart", %{
      series: [%{name: "sanbase-web-0", points: [[_, 4321]]}],
      value_kind: "count"
    })
  end
end
