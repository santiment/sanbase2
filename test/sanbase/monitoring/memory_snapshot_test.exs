defmodule Sanbase.Monitoring.MemorySnapshotTest do
  use ExUnit.Case, async: true

  alias Sanbase.Monitoring.MemorySnapshot

  test "collect/0 returns cheap scalar stats" do
    snapshot = MemorySnapshot.collect()

    assert is_integer(snapshot.vm_total_bytes) and snapshot.vm_total_bytes > 0
    assert is_integer(snapshot.vm_processes_bytes) and snapshot.vm_processes_bytes > 0
    assert is_integer(snapshot.vm_binary_bytes)
    assert is_integer(snapshot.vm_ets_bytes) and snapshot.vm_ets_bytes > 0
    assert is_integer(snapshot.vm_code_bytes) and snapshot.vm_code_bytes > 0
    assert is_integer(snapshot.process_count) and snapshot.process_count > 0
    assert is_integer(snapshot.atom_count) and snapshot.atom_count > 0
    assert is_integer(snapshot.duration_ms) and snapshot.duration_ms >= 0

    # rss/hwm are nil where /proc is unavailable (macOS)
    assert is_nil(snapshot.rss_bytes) or is_integer(snapshot.rss_bytes)
    assert is_nil(snapshot.rss_hwm_bytes) or is_integer(snapshot.rss_hwm_bytes)

    # not requested by default — it is the expensive part
    assert is_nil(snapshot.process_groups)
  end

  test "collect/0 returns top ETS tables sorted by memory" do
    %{top_ets: top_ets} = MemorySnapshot.collect(top_n: 5)

    assert length(top_ets) == 5

    for row <- top_ets do
      assert is_binary(row.name)
      assert is_integer(row.memory_bytes) and row.memory_bytes > 0
      assert is_integer(row.rows)
      assert is_binary(row.owner)
    end

    memories = Enum.map(top_ets, & &1.memory_bytes)
    assert memories == Enum.sort(memories, :desc)
  end

  test "collect/1 includes process groups when requested" do
    %{process_groups: groups} = MemorySnapshot.collect(include_process_groups: true, top_n: 10)

    assert is_list(groups)
    assert length(groups) == 10

    for row <- groups do
      assert is_binary(row.name)
      assert is_integer(row.count) and row.count > 0
      assert is_integer(row.memory_bytes) and row.memory_bytes > 0
    end
  end

  test "allocator_rows/0 reports used <= allocated per allocator" do
    rows = MemorySnapshot.allocator_rows()

    assert rows != []

    for {name, used, allocated} <- rows do
      assert is_atom(name)
      assert used <= allocated
    end
  end

  test "beam_started_at/0 is a past datetime" do
    started_at = MemorySnapshot.beam_started_at()

    assert %DateTime{} = started_at
    assert DateTime.compare(started_at, DateTime.utc_now()) == :lt
  end
end
