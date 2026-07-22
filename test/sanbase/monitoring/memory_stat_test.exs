defmodule Sanbase.Monitoring.MemoryStatTest do
  use Sanbase.DataCase, async: false

  alias Sanbase.Monitoring.MemoryCollector
  alias Sanbase.Monitoring.MemoryStat

  @beam_started_at ~U[2026-07-22 10:00:00Z]

  defp valid_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        pod_name: "sanbase-web-0",
        container_type: "web",
        beam_started_at: @beam_started_at,
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
        details: %{top_ets: [%{name: ":my_table", memory_bytes: 1000, rows: 5, owner: "X"}]}
      },
      overrides
    )
  end

  test "store/1 inserts a sample" do
    assert {:ok, stat} = MemoryStat.store(valid_attrs())
    assert stat.pod_name == "sanbase-web-0"
    assert stat.details["top_ets"] == nil
    assert %{top_ets: [_]} = stat.details
  end

  test "store/1 requires identity and vm fields" do
    assert {:error, changeset} =
             MemoryStat.store(valid_attrs(%{pod_name: nil, vm_total_bytes: nil}))

    assert %{pod_name: ["can't be blank"], vm_total_bytes: ["can't be blank"]} =
             errors_on(changeset)
  end

  test "latest_per_pod/1 returns one latest row per recently-seen pod" do
    {:ok, _old_web} = MemoryStat.store(valid_attrs(%{vm_total_bytes: 1}))
    {:ok, new_web} = MemoryStat.store(valid_attrs(%{vm_total_bytes: 2}))

    {:ok, admin} =
      MemoryStat.store(valid_attrs(%{pod_name: "sanbase-admin-x", container_type: "admin"}))

    # pod that reported too long ago is not "live"
    {:ok, stale} = MemoryStat.store(valid_attrs(%{pod_name: "sanbase-dead-pod"}))
    stale_time = NaiveDateTime.utc_now() |> NaiveDateTime.add(-3600, :second)

    Sanbase.Repo.update_all(
      from(s in MemoryStat, where: s.id == ^stale.id),
      set: [inserted_at: stale_time]
    )

    result = MemoryStat.latest_per_pod(5)

    assert length(result) == 2
    assert Enum.map(result, & &1.pod_name) == ["sanbase-admin-x", "sanbase-web-0"]
    assert Enum.find(result, &(&1.pod_name == "sanbase-web-0")).id == new_web.id
    assert Enum.find(result, &(&1.pod_name == "sanbase-admin-x")).id == admin.id
  end

  test "pod_series/2 returns scalar rows oldest first, without details" do
    {:ok, s1} = MemoryStat.store(valid_attrs(%{vm_total_bytes: 1}))
    {:ok, s2} = MemoryStat.store(valid_attrs(%{vm_total_bytes: 2}))
    {:ok, _other} = MemoryStat.store(valid_attrs(%{pod_name: "sanbase-other"}))

    series = MemoryStat.pod_series("sanbase-web-0", 24)

    assert Enum.map(series, & &1.id) == [s1.id, s2.id]
    assert [%{vm_total_bytes: 1, beam_started_at: @beam_started_at} | _] = series
    refute Map.has_key?(hd(series), :details)
  end

  test "prune/1 deletes only rows older than the cutoff" do
    {:ok, old} = MemoryStat.store(valid_attrs())
    {:ok, fresh} = MemoryStat.store(valid_attrs())

    old_time = NaiveDateTime.utc_now() |> NaiveDateTime.add(-8 * 86_400, :second)

    Sanbase.Repo.update_all(
      from(s in MemoryStat, where: s.id == ^old.id),
      set: [inserted_at: old_time]
    )

    assert {1, _} = MemoryStat.prune(7)
    assert Sanbase.Repo.get(MemoryStat, old.id) == nil
    assert Sanbase.Repo.get(MemoryStat, fresh.id)
  end

  test "collector sample/2 collects and stores a row for this node" do
    state = %{
      pod_name: "test-pod",
      container_type: "test",
      beam_started_at: @beam_started_at,
      retention_days: 7
    }

    assert {:ok, stat} = MemoryCollector.sample(state, true)

    assert stat.pod_name == "test-pod"
    assert stat.container_type == "test"
    assert stat.vm_total_bytes > 0
    assert stat.process_count > 0
    assert stat.sample_duration_ms >= 0
    assert %{top_ets: [_ | _], process_groups: [_ | _]} = stat.details

    # without the flag the expensive process-groups part is skipped
    assert {:ok, stat} = MemoryCollector.sample(state, false)
    assert %{top_ets: [_ | _]} = stat.details
    refute Map.has_key?(stat.details, :process_groups)
  end
end
