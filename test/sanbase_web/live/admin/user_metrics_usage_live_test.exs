defmodule SanbaseWeb.Admin.UserMetricsUsageLiveTest do
  use SanbaseWeb.ConnCase, async: false

  @moduletag capture_log: true

  import Mock
  import Phoenix.LiveViewTest
  import Sanbase.Factory

  alias Sanbase.Accounts.UserRole

  defp sign_in do
    user = insert(:user)
    role = insert(:role_admin_panel_viewer)
    {:ok, _user_role} = UserRole.create(user.id, role.id)
    {:ok, jwt_tokens} = SanbaseWeb.Guardian.get_jwt_tokens(user)

    Plug.Test.init_test_session(build_conn(), jwt_tokens)
  end

  defp row(query, apikey, jwt) do
    %{
      query: query,
      apikey_calls: apikey,
      jwt_calls: jwt,
      other_calls: 0,
      total_calls: apikey + jwt,
      last_called_at: ~U[2026-11-01 10:00:00Z]
    }
  end

  defp rows do
    [
      row("getMetric|price_usd", 1200, 30),
      row("getMetric|daily_active_addresses", 50, 0),
      row("getSignal|anomaly", 3, 0),
      row("allProjects", 10, 5)
    ]
  end

  defp daily do
    [
      %{date: ~D[2026-10-29], auth_method: "jwt", calls: 28, distinct_metrics: 0},
      %{date: ~D[2026-10-28], auth_method: "apikey", calls: 20_233, distinct_metrics: 1_238}
    ]
  end

  setup do
    %{conn: sign_in(), target: insert(:user, email: "target@example.com")}
  end

  test "lists the metrics the user called", %{conn: conn, target: target} do
    with_mock Sanbase.Clickhouse.ApiCallData, [:passthrough],
      user_queries_usage: fn _user_id, _from, _limit -> {:ok, rows()} end,
      user_daily_usage: fn _user_id, _from -> {:ok, daily()} end do
      {:ok, view, _html} = live(conn, ~p"/admin/user_metrics_usage?user_id=#{target.id}")
      render_async(view)

      assert has_element?(view, "#metrics-usage-user", "target@example.com")
      assert has_element?(view, "#usage-row-metric-price_usd", "1,230")
      assert has_element?(view, "#usage-row-metric-daily_active_addresses")
      # The default filter shows metrics only
      refute has_element?(view, "#usage-row-signal-anomaly")
      refute has_element?(view, "#usage-row-query-allProjects")
      assert has_element?(view, "#metrics-usage-summary", "Distinct metrics")
      assert has_element?(view, "#daily-row-2026-10-28-apikey", "20,233")
      assert has_element?(view, "#daily-row-2026-10-28-apikey", "1,238")
      assert has_element?(view, "#daily-row-2026-10-29-jwt")
    end
  end

  test "the All filter shows signals and other queries without re-querying",
       %{conn: conn, target: target} do
    test_pid = self()

    with_mock Sanbase.Clickhouse.ApiCallData, [:passthrough],
      user_queries_usage: fn _user_id, _from, _limit ->
        send(test_pid, :queried)
        {:ok, rows()}
      end,
      user_daily_usage: fn _user_id, _from -> {:ok, daily()} end do
      {:ok, view, _html} = live(conn, ~p"/admin/user_metrics_usage?user_id=#{target.id}")
      render_async(view)
      assert_received :queried

      view |> element("#kind-all") |> render_click()

      assert has_element?(view, "#usage-row-signal-anomaly")
      assert has_element?(view, "#usage-row-query-allProjects")
      refute_received :queried

      view |> element("#period-90") |> render_click()
      render_async(view)
      assert_received :queried
    end
  end

  test "shows an error for an unknown user", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/user_metrics_usage?user_id=999999999")

    assert has_element?(view, "#metrics-usage-error", "not found")
  end
end
