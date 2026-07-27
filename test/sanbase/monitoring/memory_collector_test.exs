defmodule Sanbase.Monitoring.MemoryCollectorTest do
  use Sanbase.DataCase, async: false

  import ExUnit.CaptureLog

  alias Sanbase.Monitoring.MemoryCollector
  alias Sanbase.Monitoring.MemoryStat

  @beam_started_at ~U[2026-07-22 10:00:00Z]

  # The collector reads its own config at runtime, so these tests swap the
  # whole app-env entry and put the test config back afterwards.
  defp with_config(config, fun) do
    original = Application.get_env(:sanbase, MemoryCollector)

    try do
      Application.put_env(:sanbase, MemoryCollector, config)
      fun.()
    after
      Application.put_env(:sanbase, MemoryCollector, original)
    end
  end

  # init/1 schedules the first tick; an hour-long interval keeps that timer
  # from firing into the test process before the test ends.
  defp init_state(config, opts \\ []) do
    with_config(config, fn ->
      {:ok, state} = MemoryCollector.init(Keyword.put_new(opts, :interval, :timer.hours(1)))
      state
    end)
  end

  defp state(overrides \\ %{}) do
    Map.merge(
      %{
        pod_name: "test-pod",
        container_type: "test",
        beam_started_at: @beam_started_at,
        retention_days: 7
      },
      overrides
    )
  end

  describe "enabled?/0" do
    test "is on when nothing is configured" do
      original = Application.get_env(:sanbase, MemoryCollector)

      try do
        Application.delete_env(:sanbase, MemoryCollector)
        assert MemoryCollector.enabled?()
      after
        Application.put_env(:sanbase, MemoryCollector, original)
      end
    end

    test "accepts booleans and the string/integer forms an env var can carry" do
      for value <- [true, "true", "TRUE", 1, "1"] do
        with_config([enabled: value], fn -> assert MemoryCollector.enabled?() end)
      end

      for value <- [false, "false", "FALSE", 0, "0"] do
        with_config([enabled: value], fn -> refute MemoryCollector.enabled?() end)
      end
    end

    test "resolves the {:system, ...} env var form" do
      with_config([enabled: {:system, "MEMORY_COLLECTOR_ENABLED_TEST_UNSET", "false"}], fn ->
        refute MemoryCollector.enabled?()
      end)
    end

    test "stays enabled and warns on an unrecognized value" do
      log =
        capture_log(fn ->
          with_config([enabled: "yes"], fn -> assert MemoryCollector.enabled?() end)
        end)

      assert log =~ "unrecognized MEMORY_COLLECTOR_ENABLED value"
    end
  end

  describe "init/1 retention" do
    test "takes an integer or a numeric string" do
      assert %{retention_days: 30} = init_state(retention_days: 30)
      assert %{retention_days: 45} = init_state(retention_days: "45")
      assert %{retention_days: 45} = init_state(retention_days: " 45 ")
    end

    test "defaults to 90 days when unconfigured" do
      assert %{retention_days: 90} = init_state([])
    end

    test "falls back to the default and warns on an unusable value" do
      for value <- ["not-a-number", "0", "-5", nil] do
        log =
          capture_log(fn ->
            assert %{retention_days: 90} = init_state(retention_days: value)
          end)

        assert log =~ "invalid MEMORY_COLLECTOR_RETENTION_DAYS value"
      end
    end

    test "an explicit opt wins over the config" do
      assert %{retention_days: 5} = init_state([retention_days: 30], retention_days: 5)
    end
  end

  describe "tick schedule" do
    test "process groups are collected on the first sample and every 5th after" do
      collected = for tick <- 1..11, MemoryCollector.collect_process_groups?(tick), do: tick

      assert collected == [1, 6, 11]
    end

    test "pruning runs once per 60 samples, never on the first" do
      due = for tick <- 1..121, MemoryCollector.prune_due?(tick), do: tick

      assert due == [60, 120]
    end
  end

  describe "sample/2" do
    test "collects and stores a row for this node" do
      assert {:ok, stat} = MemoryCollector.sample(state(), true)

      assert stat.pod_name == "test-pod"
      assert stat.container_type == "test"
      assert stat.vm_total_bytes > 0
      assert stat.process_count > 0
      assert stat.sample_duration_ms >= 0
      assert %{top_ets: [_ | _], process_groups: [_ | _]} = stat.details

      # without the flag the expensive process-groups part is skipped
      assert {:ok, stat} = MemoryCollector.sample(state(), false)
      assert %{top_ets: [_ | _]} = stat.details
      refute Map.has_key?(stat.details, :process_groups)
    end

    test "an unstorable sample warns instead of raising" do
      log =
        capture_log(fn ->
          assert {:error, changeset} = MemoryCollector.sample(state(%{pod_name: nil}), false)
          assert %{pod_name: ["can't be blank"]} = errors_on(changeset)
        end)

      assert log =~ "failed to store sample"
    end
  end

  describe "prune/1" do
    test "logs nothing when the window covers every row" do
      {:ok, _} = MemoryCollector.sample(state(), false)

      log = capture_log(fn -> assert :ok = MemoryCollector.prune(state()) end)

      refute log =~ "pruned"
      assert MemoryStat.latest_for_pod("test-pod")
    end

    test "deletes past the retention window and says how many rows went" do
      {:ok, stat} = MemoryCollector.sample(state(), false)
      backdate(stat, 8 * 86_400)

      log = capture_log(fn -> assert :ok = MemoryCollector.prune(state()) end)

      assert log =~ "pruned 1 node_memory_stats rows older than 7 days"
      refute MemoryStat.latest_for_pod("test-pod")
    end
  end

  defp backdate(stat, seconds_ago) do
    at = NaiveDateTime.utc_now() |> NaiveDateTime.add(-seconds_ago, :second)

    Sanbase.Repo.update_all(
      from(s in MemoryStat, where: s.id == ^stat.id),
      set: [inserted_at: at]
    )
  end
end
