defmodule Sanbase.Monitoring.MemoryStatTest do
  use Sanbase.DataCase, async: false

  import Sanbase.Factory

  alias Sanbase.Monitoring.MemoryStat

  @beam_started_at ~U[2026-07-22 10:00:00Z]

  # Charts bucket by time, so tests that care about more than one point must
  # place their samples apart rather than inserting them all in one instant.
  defp store_at(overrides, seconds_ago) do
    {:ok, stat} = MemoryStat.store(valid_attrs(overrides))
    at = NaiveDateTime.utc_now() |> NaiveDateTime.add(-seconds_ago, :second)

    Sanbase.Repo.update_all(
      from(s in MemoryStat, where: s.id == ^stat.id),
      set: [inserted_at: at]
    )

    %{stat | inserted_at: at}
  end

  # store/1 takes attrs, so drop what Ecto owns off the factory struct and
  # merge the overrides — explicit nils included, they are the "gap" cases.
  defp valid_attrs(overrides \\ %{}) do
    build(:memory_stat)
    |> Map.from_struct()
    |> Map.drop([:__meta__, :id, :inserted_at, :updated_at])
    |> Map.merge(overrides)
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

  test "multi_pod_metric_series/3 returns per-pod points, keeping nil samples as gaps" do
    store_at(%{rss_bytes: 100}, 240)
    store_at(%{rss_bytes: 200}, 180)
    store_at(%{pod_name: "sanbase-web-1", rss_bytes: 300}, 240)
    # a sample that recorded no value is a hole in the data, not a missing row:
    # the chart has to break the line there instead of drawing across it
    store_at(%{pod_name: "sanbase-web-1", rss_bytes: nil}, 180)

    series =
      MemoryStat.multi_pod_metric_series(["sanbase-web-0", "sanbase-web-1"], :rss_bytes, 24)

    assert [
             %{name: "sanbase-web-0", points: [[t1, 100], [_t2, 200]]},
             %{name: "sanbase-web-1", points: [[_t3, 300], [_t4, nil]]}
           ] = series

    assert is_integer(t1)
  end

  test "multi_pod_metric_series/4 buckets long windows and keeps each bucket's peak" do
    # a one-sample spike in the middle of an otherwise flat series
    for minutes <- 1..10 do
      value = if minutes == 4, do: 900, else: 100
      store_at(%{rss_bytes: value}, minutes * 60)
    end

    [%{points: points}] = MemoryStat.multi_pod_metric_series(["sanbase-web-0"], :rss_bytes, 1, 5)

    # 10 minutes of samples collapsed into 720s buckets
    assert length(points) <= 2
    # the spike survives bucketing — a stride would have been free to skip it
    assert Enum.max(for [_t, value] <- points, do: value) == 900
  end

  test "multi_pod_metric_series/4 keeps full resolution on short windows" do
    for minutes <- 1..5, do: store_at(%{rss_bytes: minutes * 10}, minutes * 60)

    [%{points: points}] = MemoryStat.multi_pod_metric_series(["sanbase-web-0"], :rss_bytes, 1)

    assert length(points) == 5
    assert Enum.map(points, fn [_t, value] -> value end) == [50, 40, 30, 20, 10]
  end

  test "labeled_series/3 returns one series per label, keeping nil samples as gaps" do
    store_at(%{}, 120)
    store_at(%{rss_bytes: nil}, 60)

    rows = MemoryStat.pod_series("sanbase-web-0", 24)

    assert [
             %{name: "OS RSS", points: [[t1, 1_500_000_000], [_t2, nil]]},
             %{name: "VM total", points: [[_, 1_200_000_000], [_, 1_200_000_000]]}
           ] =
             MemoryStat.labeled_series(rows, [
               {"OS RSS", :rss_bytes},
               {"VM total", :vm_total_bytes}
             ])

    assert is_integer(t1)
  end

  test "labeled_series/3 takes a function for values derived from several fields" do
    {:ok, _} = MemoryStat.store(valid_attrs())

    rows = MemoryStat.pod_series("sanbase-web-0", 24)

    assert [%{name: "Allocator utilization", points: [[_, 78.6]]}] =
             MemoryStat.labeled_series(rows, [
               {"Allocator utilization", &MemoryStat.utilization/1}
             ])
  end

  test "labeled_series/3 downsamples to max_points, keeping each bucket's peak" do
    # a one-sample spike in the middle of an otherwise flat series
    for minutes <- 1..10 do
      value = if minutes == 4, do: 900_000_000, else: 100_000_000
      store_at(%{rss_bytes: value}, minutes * 60)
    end

    rows = MemoryStat.pod_series("sanbase-web-0", 24)

    assert [%{points: points}] = MemoryStat.labeled_series(rows, [{"OS RSS", :rss_bytes}], 5)

    assert length(points) == 5
    # the spike survives downsampling — a stride would have been free to skip it
    assert Enum.max(for [_t, value] <- points, do: value) == 900_000_000
  end

  test "utilization/1 is used blocks over allocated carriers" do
    # 1.1e9 / 1.4e9 = 78.6%
    assert MemoryStat.utilization(%{
             alloc_used_bytes: 1_100_000_000,
             alloc_allocated_bytes: 1_400_000_000
           }) == 78.6

    assert MemoryStat.utilization(%{alloc_used_bytes: nil, alloc_allocated_bytes: nil}) == nil
    assert MemoryStat.utilization(%{alloc_used_bytes: 1, alloc_allocated_bytes: 0}) == nil
  end

  test "known_pods/2 aggregates per pod within the window, newest reporter first" do
    store_at(%{pod_name: "sanbase-web-0"}, 600)
    store_at(%{pod_name: "sanbase-web-0"}, 60)
    store_at(%{pod_name: "sanbase-admin-x", container_type: "admin"}, 300)
    # outside the default 7d window
    store_at(%{pod_name: "sanbase-ancient"}, 8 * 86_400)

    assert [
             %{pod_name: "sanbase-web-0", container_type: "web", samples: 2} = web,
             %{pod_name: "sanbase-admin-x", container_type: "admin", samples: 1}
           ] = MemoryStat.known_pods()

    # ~9 minutes apart; the exact diff depends on where the second-precision
    # column truncates each timestamp
    assert NaiveDateTime.diff(web.last_seen, web.first_seen) in 539..541
  end

  test "known_pods/2 honours the limit and the window override" do
    store_at(%{pod_name: "sanbase-web-0"}, 60)
    store_at(%{pod_name: "sanbase-web-1"}, 120)
    store_at(%{pod_name: "sanbase-ancient"}, 8 * 86_400)

    assert [%{pod_name: "sanbase-web-0"}] = MemoryStat.known_pods(1)

    pods = MemoryStat.known_pods(100, 30) |> Enum.map(& &1.pod_name)
    assert "sanbase-ancient" in pods
  end

  test "latest_per_pod/1 counts a pod live right up to the window edge" do
    store_at(%{pod_name: "sanbase-just-inside"}, 4 * 60)
    store_at(%{pod_name: "sanbase-just-outside"}, 6 * 60)

    assert [%{pod_name: "sanbase-just-inside"}] = MemoryStat.latest_per_pod(5)
  end

  test "pod_series/2 excludes samples older than the window" do
    inside = store_at(%{vm_total_bytes: 1}, 30 * 60)
    _outside = store_at(%{vm_total_bytes: 2}, 90 * 60)

    assert [%{id: id}] = MemoryStat.pod_series("sanbase-web-0", 1)
    assert id == inside.id
  end

  test "latest_details/1 prefers the newest sample that carries process groups" do
    with_groups =
      store_at(
        %{details: %{top_ets: [], process_groups: [%{name: "X", count: 1, memory_bytes: 1}]}},
        300
      )

    # newer samples, but process groups are only collected on every Nth one
    for seconds_ago <- [240, 180, 120, 60],
        do: store_at(%{details: %{top_ets: []}}, seconds_ago)

    assert MemoryStat.latest_details("sanbase-web-0").id == with_groups.id
  end

  test "latest_details/1 falls back to the newest sample when none has groups" do
    _older = store_at(%{details: %{top_ets: []}}, 120)
    newest = store_at(%{details: %{top_ets: []}}, 60)

    assert MemoryStat.latest_details("sanbase-web-0").id == newest.id
  end

  test "latest_details/1 returns nil for a pod that never reported" do
    assert MemoryStat.latest_details("sanbase-never-seen") == nil
  end
end
