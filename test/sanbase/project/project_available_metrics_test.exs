defmodule Sanbase.Project.AvailableMetricsTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  setup do
    # Re-enable the RC branch in `ProjectMetricsResolver` for this file only so
    # the resolver ↔ RehydratingCache integration is exercised end-to-end.
    # `on_exit` restores the test-default (false) so later files stay isolated.
    Application.put_env(:sanbase, :use_rehydrating_cache, true)
    on_exit(fn -> Application.put_env(:sanbase, :use_rehydrating_cache, false) end)

    # Per-test RC supervisor. No manual `stop_supervised` needed: ExUnit tracks
    # everything started via `start_supervised!/1` under a test-owned supervisor
    # and shuts them down in reverse start order when the test exits (pass, fail,
    # or crash). That tears down the RC GenServer, its ConCache store, and the
    # Task.Supervisor — so no closure leaks into later tests. `async: false` above
    # is required because the RC supervisor registers fixed atoms
    # (e.g. `:__rehydrating_cache__`), which can't coexist across parallel tests.
    start_supervised!(Sanbase.Cache.RehydratingCache.Supervisor)

    :ok
  end

  test "get project's available metrics" do
    project = insert(:random_erc20_project)
    available_metrics = Sanbase.Metric.available_metrics()

    metrics =
      available_metrics |> Enum.shuffle() |> Enum.take(Enum.random(1..length(available_metrics)))

    Sanbase.Mock.prepare_mock2(&Sanbase.Metric.available_metrics_for_selector/2, {:ok, metrics})
    |> Sanbase.Mock.run_with_mocks(fn ->
      result = get_available_metrics(build_conn(), project)
      %{"data" => %{"projectBySlug" => %{"availableMetrics" => available_metrics}}} = result

      assert available_metrics == metrics
    end)
  end

  describe "available_metrics_lookback_days" do
    test "passes the authenticated user's lookback_days to the facade" do
      user = insert(:user, available_metrics_lookback_days: 365)
      project = insert(:random_erc20_project)
      test_pid = self()

      Sanbase.Mock.prepare_mock(
        Sanbase.Metric,
        :available_metrics_for_selector,
        fn _selector, opts ->
          send(test_pid, {:facade_called, Keyword.get(opts, :lookback_days)})
          {:ok, ["daily_active_addresses"]}
        end
      )
      |> Sanbase.Mock.run_with_mocks(fn ->
        build_conn()
        |> setup_jwt_auth(user)
        |> get_available_metrics(project)

        assert_receive {:facade_called, 365}, 2_000
      end)
    end

    test "passes nil when the user has no lookback_days set" do
      user = insert(:user)
      project = insert(:random_erc20_project)
      test_pid = self()

      Sanbase.Mock.prepare_mock(
        Sanbase.Metric,
        :available_metrics_for_selector,
        fn _selector, opts ->
          send(test_pid, {:facade_called, Keyword.get(opts, :lookback_days)})
          {:ok, []}
        end
      )
      |> Sanbase.Mock.run_with_mocks(fn ->
        build_conn()
        |> setup_jwt_auth(user)
        |> get_available_metrics(project)

        assert_receive {:facade_called, nil}, 2_000
      end)
    end

    test "users with different lookback_days get separately cached results" do
      user_a = insert(:user, available_metrics_lookback_days: 30)
      user_b = insert(:user, available_metrics_lookback_days: 365)
      project = insert(:random_erc20_project)
      test_pid = self()

      Sanbase.Mock.prepare_mock(
        Sanbase.Metric,
        :available_metrics_for_selector,
        fn _selector, opts ->
          days = Keyword.get(opts, :lookback_days)
          send(test_pid, {:facade_called, days})
          {:ok, ["metric_for_#{days}"]}
        end
      )
      |> Sanbase.Mock.run_with_mocks(fn ->
        result_a =
          build_conn() |> setup_jwt_auth(user_a) |> get_available_metrics(project)

        result_b =
          build_conn() |> setup_jwt_auth(user_b) |> get_available_metrics(project)

        assert %{"data" => %{"projectBySlug" => %{"availableMetrics" => ["metric_for_30"]}}} =
                 result_a

        assert %{"data" => %{"projectBySlug" => %{"availableMetrics" => ["metric_for_365"]}}} =
                 result_b

        # Both reached the facade — keys did not collide
        assert_receive {:facade_called, 30}, 2_000
        assert_receive {:facade_called, 365}, 2_000
      end)
    end

    test "same user hits cache on repeat calls (facade invoked once)" do
      user = insert(:user, available_metrics_lookback_days: 90)
      project = insert(:random_erc20_project)
      test_pid = self()

      Sanbase.Mock.prepare_mock(
        Sanbase.Metric,
        :available_metrics_for_selector,
        fn _selector, _opts ->
          send(test_pid, :facade_called)
          {:ok, ["daily_active_addresses"]}
        end
      )
      |> Sanbase.Mock.run_with_mocks(fn ->
        conn = build_conn() |> setup_jwt_auth(user)

        get_available_metrics(conn, project)
        get_available_metrics(conn, project)

        assert_receive :facade_called, 2_000
        refute_receive :facade_called, 500
      end)
    end
  end

  defp get_available_metrics(conn, project) do
    query = """
    {
      projectBySlug(slug: "#{project.slug}"){
        availableMetrics
      }
    }
    """

    conn
    |> post("/graphql", query_skeleton(query))
    |> json_response(200)
  end
end
