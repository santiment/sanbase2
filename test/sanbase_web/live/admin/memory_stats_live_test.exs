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

  defp insert_stat(overrides), do: insert(:memory_stat, overrides)

  defp make_stale(stat, seconds_ago) do
    at = NaiveDateTime.utc_now() |> NaiveDateTime.add(-seconds_ago, :second)

    Sanbase.Repo.update_all(
      from(s in MemoryStat, where: s.id == ^stat.id),
      set: [inserted_at: at]
    )

    stat
  end

  test "renders empty state when no pods reported", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/admin/memory_stats")

    assert has_element?(view, "h1", "Memory Stats")
    assert has_element?(view, "#no-pods", "No pods reported recently")
  end

  test "warns that nothing is collected while the collector is disabled", %{conn: conn} do
    # config/test.exs sets enabled: false for Sanbase.Monitoring.MemoryCollector
    {:ok, view, _html} = live(conn, "/admin/memory_stats")

    assert has_element?(view, "#collector-disabled-warning", "Memory collection is off")
    assert has_element?(view, "#collector-disabled-warning code", "MEMORY_COLLECTOR_ENABLED=true")
  end

  test "lists live pods with their latest sample", %{conn: conn} do
    insert_stat(%{})
    insert_stat(%{pod_name: "sanbase-admin-x", container_type: "admin"})

    {:ok, view, _html} = live(conn, "/admin/memory_stats")

    assert has_element?(view, "#live-pod-sanbase-web-0")
    assert has_element?(view, "#live-pod-sanbase-admin-x")
    assert has_element?(view, "#live-pod-sanbase-web-0 td", "1.12 GB")
  end

  test "selecting a pod shows latest sample, details and samples", %{conn: conn} do
    insert_stat(%{vm_total_bytes: 1_000_000_000})
    insert_stat(%{vm_total_bytes: 1_200_000_000})

    {:ok, view, _html} = live(conn, "/admin/memory_stats?pod=sanbase-web-0")

    assert has_element?(view, "#latest-sample h2", "sanbase-web-0 · latest sample")
    # too few samples for the smoothed window stats
    refute has_element?(view, "#window-stats")
    # details from the sample that has process groups
    assert has_element?(view, "#top-ets td", ":graphql_cache")
    assert has_element?(view, "#process-groups td", "Sanbase.BigProcess")
    assert has_element?(view, "#recent-samples")
  end

  test "window stats show min/avg/max and a smoothed trend", %{conn: conn} do
    # 10 low samples then 10 high ones: trend = avg(last 5) - avg(first 5)
    for _ <- 1..10, do: insert_stat(%{vm_total_bytes: 1_000_000_000})
    for _ <- 1..10, do: insert_stat(%{vm_total_bytes: 2_000_000_000})

    {:ok, view, _html} = live(conn, "/admin/memory_stats?pod=sanbase-web-0")

    assert has_element?(view, "#window-stats h2", "Window stats, current incarnation")
    assert has_element?(view, "#window-stats th", "Trend")
    # derived components computed per sample
    assert has_element?(view, "#window-stats td", "Carrier slack (allocated − used)")
    assert has_element?(view, "#window-stats td", "Native/other (RSS − allocated)")
    assert has_element?(view, "#window-stats td", "RSS high-water")
    # min 1e9 bytes = 953.7 MB, max 2e9 = 1.86 GB (GiB-based),
    # trend = last-5 avg minus first-5 avg = +1e9
    assert has_element?(view, "#window-stats td", "953.7 MB")
    assert has_element?(view, "#window-stats td", "1.86 GB")
    assert has_element?(view, "#window-stats td", "+953.7 MB")
  end

  test "clicking a pod in the live table patches to that pod's view", %{conn: conn} do
    insert_stat(%{})

    {:ok, view, _html} = live(conn, "/admin/memory_stats")

    view |> element("#live-pod-sanbase-web-0 a") |> render_click()

    assert_patched(view, "/admin/memory_stats?pod=sanbase-web-0")
    assert has_element?(view, "#latest-sample h2", "sanbase-web-0 · latest sample")
    assert_push_event(view, "chart-data-pod-chart", %{series: [%{name: "OS RSS"} | _]})
  end

  test "selecting a pod with no recorded samples shows only a warning", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/admin/memory_stats?pod=sanbase-gone-pod")

    assert has_element?(
             view,
             "#no-samples-warning",
             "No samples recorded for pod sanbase-gone-pod"
           )

    refute has_element?(view, "#latest-sample")
  end

  test "known pods table lists non-live pods with oldest/newest snapshots", %{conn: conn} do
    insert_stat(%{pod_name: "sanbase-live-pod"})
    insert_stat(%{pod_name: "sanbase-old-deploy"}) |> make_stale(3600)

    {:ok, view, _html} = live(conn, "/admin/memory_stats")

    assert has_element?(view, "#known-pods h2", "Known pods, not reporting now")
    assert has_element?(view, "#known-pod-sanbase-old-deploy")
    # live pod is not repeated in the known-pods table section
    refute has_element?(view, "#known-pod-sanbase-live-pod")
    assert has_element?(view, "#known-pods th", "Oldest snapshot (UTC)")
  end

  test "a stale pod shows the warning AND its recorded history", %{conn: conn} do
    insert_stat(%{pod_name: "sanbase-old-deploy"}) |> make_stale(1800)

    {:ok, view, _html} = live(conn, "/admin/memory_stats?pod=sanbase-old-deploy")

    assert has_element?(view, "#stale-pod-warning", "has not reported in the last")
    assert has_element?(view, "#stale-pod-warning", "showing its recorded history")
    # data sections still render
    assert has_element?(view, "#latest-sample h2", "sanbase-old-deploy · latest sample")
    assert has_element?(view, "#top-ets td", ":graphql_cache")
    assert has_element?(view, "#recent-samples")

    assert_push_event(view, "chart-data-pod-chart", %{series: [%{name: "OS RSS"} | _]})
  end

  test "renders charts and pushes series data to the hooks", %{conn: conn} do
    insert_stat(%{rss_bytes: 100})
    insert_stat(%{pod_name: "sanbase-web-1", rss_bytes: 200})

    {:ok, view, _html} = live(conn, "/admin/memory_stats?pod=sanbase-web-0")

    assert has_element?(view, ~s|#overview-chart[phx-hook="TimeseriesChart"]|)
    assert has_element?(view, ~s|#pod-chart[phx-hook="TimeseriesChart"]|)

    assert_push_event(view, "chart-data-overview-chart", %{
      series: [%{name: "sanbase-web-0"}, %{name: "sanbase-web-1"}],
      value_kind: "bytes"
    })

    assert_push_event(view, "chart-data-pod-chart", %{series: [%{name: "OS RSS"} | _]})
  end

  test "default chart metric falls back to VM total when no pod reports RSS", %{conn: conn} do
    insert_stat(%{rss_bytes: nil})

    {:ok, view, _html} = live(conn, "/admin/memory_stats")

    assert has_element?(view, "#overview-chart-title", "VM total · all live pods")

    assert_push_event(view, "chart-data-overview-chart", %{
      series: [%{name: "sanbase-web-0", points: [[_, 1_200_000_000]]}],
      value_kind: "bytes"
    })
  end

  test "pod chart mode switches between buckets, layers and alloc util", %{conn: conn} do
    insert_stat(%{})

    {:ok, view, _html} = live(conn, "/admin/memory_stats?pod=sanbase-web-0")

    assert has_element?(view, "#pod-chart-title", "Buckets")

    assert_push_event(view, "chart-data-pod-chart", %{
      series: [%{name: "OS RSS"} | _],
      value_kind: "bytes"
    })

    view |> element("#pod-chart-section button", "Layers") |> render_click()

    assert has_element?(view, "#pod-chart-title", "Layers (leak vs ratchet)")
    assert has_element?(view, "#pod-chart-section p", "carrier slack")

    assert_push_event(view, "chart-data-pod-chart", %{
      series: [%{name: "RSS high-water"} | _],
      value_kind: "bytes"
    })

    view |> element("#pod-chart-section button", "Alloc utilization") |> render_click()

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
    view |> element("#overview-chart-section button", "VM total") |> render_click()

    assert has_element?(view, "#overview-chart-title", "OS RSS + VM total · all live pods")

    assert_push_event(view, "chart-data-overview-chart", %{
      series: [
        %{name: "sanbase-web-0 · OS RSS", points: [[_, 100]]},
        %{name: "sanbase-web-0 · VM total", points: [[_, 200]]}
      ],
      value_kind: "bytes"
    })

    # toggling the last remaining metric off is a no-op
    view |> element("#overview-chart-section button", "VM total") |> render_click()
    view |> element("#overview-chart-section button", "OS RSS") |> render_click()

    assert has_element?(view, "#overview-chart-title", "OS RSS · all live pods")
  end

  test "process count badge is exclusive and window badges switch", %{conn: conn} do
    insert_stat(%{process_count: 4321})

    {:ok, view, _html} = live(conn, "/admin/memory_stats")

    view |> element("#overview-chart-section button", "VM total") |> render_click()
    view |> element("#overview-chart-section button", "Process count") |> render_click()

    # counts cannot share the bytes axis — selecting it drops the others
    assert has_element?(view, "#overview-chart-title", "Process count · all live pods")

    view |> element("#overview-chart-section button", "6h") |> render_click()

    assert has_element?(view, "#overview-chart-title", "last 6h")

    assert_push_event(view, "chart-data-overview-chart", %{
      series: [%{name: "sanbase-web-0", points: [[_, 4321]]}],
      value_kind: "count"
    })
  end
end
