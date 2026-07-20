# Load test / benchmark for SanbaseWeb.Graphql.CachexProvider.
#
# Exercises the exact failure modes that caused the Cachex 4 OOM incident:
#   1. Cache stampede — N concurrent callers, one computation
#   2. Bounded growth — burst writes must not grow ETS far past max_entries
#      (the OOM happened when the v4 upgrade silently dropped the limit)
#   3. Sustained mixed read/write throughput + latency percentiles
#   4. Oversized value rejection (compressed > 500kb is not cached)
#   5. TTL expiration sweep reclaims memory
#   6. Memory footprint at controlled cache-hit ratios (90% / 50% / 10%)
#   7. Parallel-friendliness — caller-process execution, lock throughput
#      scaling on distinct keys, same-key contention, process mailbox scan
#
# Runs WITHOUT booting the Sanbase application — no Postgres, no ClickHouse,
# no Kafka. Only :cachex is started.
#
# Usage:
#   mix run --no-start load_test/scripts/cachex_provider_bench.exs
#
# Tunables (env vars):
#   BENCH_DURATION_MS   - duration of the throughput scenario (default 5000)
#   BENCH_WORKERS       - concurrent workers (default 4 * schedulers)
#   BENCH_MAX_ENTRIES   - cache bound for the bounded-growth scenario (default 50_000)
#   BENCH_HITRATIO_OPS  - get_or_store calls per hit-ratio scenario (default 50_000)

defmodule CachexProviderBench do
  alias SanbaseWeb.Graphql.CachexProvider, as: Provider

  @cache :cachex_bench_cache

  def run() do
    setup()

    IO.puts("\n=== CachexProvider benchmark (cachex #{cachex_version()}) ===")
    IO.puts("schedulers: #{System.schedulers_online()}\n")

    stampede_scenario()
    bounded_growth_scenario()
    throughput_scenario()
    oversized_value_scenario()
    ttl_expiry_scenario()

    for ratio <- [0.9, 0.5, 0.1], do: hit_ratio_scenario(ratio)

    parallelism_scenario()

    IO.puts("\nAll scenarios passed.")
  end

  # --- Setup ----------------------------------------------------------------

  defp setup() do
    {:ok, _} = Application.ensure_all_started(:cachex)

    :ok
  end

  # Starts a provider-backed cache and returns its name for use in calls.
  defp start_cache(name, opts) do
    {:ok, _pid} = Provider.start_link(Keyword.merge([name: name, id: name], opts))
    name
  end

  # The Cachex supervisor is registered under the cache name.
  defp stop_cache(name) do
    name
    |> Process.whereis()
    |> Supervisor.stop(:normal)
  end

  defp cachex_version() do
    Application.spec(:cachex, :vsn) |> to_string()
  end

  # --- Scenario 1: stampede -------------------------------------------------

  defp stampede_scenario() do
    header("1. Cache stampede — 500 concurrent callers, same key")

    cache = start_cache(:"#{@cache}_stampede", [])
    counter = :counters.new(1, [])

    compute = fn ->
      :counters.add(counter, 1, 1)
      Process.sleep(50)
      {:ok, :expensive_result}
    end

    {elapsed_ms, results} =
      time(fn ->
        1..500
        |> Task.async_stream(
          fn _ -> Provider.get_or_store(cache, "hot_key", compute, & &1) end,
          max_concurrency: 500,
          timeout: :infinity
        )
        |> Enum.map(fn {:ok, res} -> res end)
      end)

    executions = :counters.get(counter, 1)

    assert!(executions == 1, "compute ran #{executions} times, expected 1")
    assert!(Enum.all?(results, &(&1 == {:ok, :expensive_result})), "not all callers got value")

    report([
      {"compute executions", executions},
      {"callers served", length(results)},
      {"wall time", "#{elapsed_ms} ms"}
    ])
  end

  # --- Scenario 2: bounded growth (the OOM regression test) ------------------

  defp bounded_growth_scenario() do
    max_entries = env_int("BENCH_MAX_ENTRIES", 50_000)
    writers = env_int("BENCH_WORKERS", System.schedulers_online() * 4)
    keys_per_writer = div(max_entries * 8, writers)

    header(
      "2. Bounded growth — #{writers} writers × #{keys_per_writer} unique keys, " <>
        "max_entries=#{max_entries}"
    )

    name = start_cache(:"#{@cache}_bounded", max_entries: max_entries, reclaim: 0.3)

    mem_before = beam_mb()

    sampler = start_sampler(fn -> Provider.count(name) end)

    {elapsed_ms, _} =
      time(fn ->
        1..writers
        |> Task.async_stream(
          fn w ->
            for i <- 1..keys_per_writer do
              Provider.store(name, "w#{w}_k#{i}", {:ok, i})
            end
          end,
          max_concurrency: writers,
          timeout: :infinity
        )
        |> Stream.run()
      end)

    # Let the evented limit hook drain its mailbox, then measure.
    Process.sleep(500)
    peak = stop_sampler(sampler)
    final_count = Provider.count(name)
    total_written = writers * keys_per_writer

    # The evented hook prunes reactively; some overshoot is expected while the
    # hook mailbox drains, but it must stay in the vicinity of the limit, not
    # at the total number of writes (which is what an unbounded cache shows).
    overshoot_limit = trunc(max_entries * 1.5)

    assert!(
      final_count <= max_entries,
      "final count #{final_count} exceeds max_entries #{max_entries}"
    )

    assert!(
      peak <= overshoot_limit,
      "peak entry count #{peak} exceeded #{overshoot_limit} " <>
        "(1.5 × max_entries) — eviction is not keeping up; unbounded-cache regression?"
    )

    report([
      {"keys written", total_written},
      {"peak entry count", "#{peak} (limit #{max_entries}, allowed overshoot ×1.5)"},
      {"final entry count", final_count},
      {"ETS size", "#{Provider.size(name)} MB"},
      {"BEAM memory", "#{mem_before} MB → #{beam_mb()} MB"},
      {"write throughput", "#{rate(total_written, elapsed_ms)} ops/s"},
      {"wall time", "#{elapsed_ms} ms"}
    ])
  end

  # --- Scenario 3: sustained mixed throughput --------------------------------

  defp throughput_scenario() do
    duration_ms = env_int("BENCH_DURATION_MS", 5_000)
    workers = env_int("BENCH_WORKERS", System.schedulers_online() * 4)

    header("3. Mixed load — #{workers} workers, #{duration_ms} ms, 90% hot / 10% unique keys")

    name = start_cache(:"#{@cache}_mixed", max_entries: 200_000)
    deadline = System.monotonic_time(:millisecond) + duration_ms

    results =
      1..workers
      |> Task.async_stream(fn _ -> mixed_worker(name, deadline, []) end,
        max_concurrency: workers,
        timeout: :infinity
      )
      |> Enum.flat_map(fn {:ok, latencies} -> latencies end)

    total_ops = length(results)
    sorted = Enum.sort(results)

    report([
      {"total ops", total_ops},
      {"throughput", "#{rate(total_ops, duration_ms)} ops/s"},
      {"latency p50", "#{percentile(sorted, 50)} µs"},
      {"latency p95", "#{percentile(sorted, 95)} µs"},
      {"latency p99", "#{percentile(sorted, 99)} µs"},
      {"max mailbox (any process)", max_mailbox()},
      {"entries", Provider.count(name)},
      {"ETS size", "#{Provider.size(name)} MB"}
    ])
  end

  defp mixed_worker(cache, deadline, acc) do
    if System.monotonic_time(:millisecond) >= deadline do
      acc
    else
      key =
        if :rand.uniform(10) == 1 do
          "unique_#{:erlang.unique_integer([:positive])}"
        else
          "hot_#{:rand.uniform(1_000)}"
        end

      {us, _} =
        :timer.tc(fn ->
          Provider.get_or_store(cache, {key, 300}, fn -> {:ok, {key, :value}} end, & &1)
        end)

      mixed_worker(cache, deadline, [us | acc])
    end
  end

  # --- Scenario 4: oversized values ------------------------------------------

  defp oversized_value_scenario() do
    header("4. Oversized values — compressed > 500kb must not be cached")

    name = start_cache(:"#{@cache}_oversized", [])

    # Random bytes do not compress below the cap
    huge = {:ok, :crypto.strong_rand_bytes(1_000_000)}
    small = {:ok, :crypto.strong_rand_bytes(1_000)}

    Provider.store(name, "huge", huge)
    Provider.store(name, "small", small)

    assert!(Provider.get(name, "huge") == nil, "oversized value was cached")
    assert!(Provider.get(name, "small") == small, "small value was not cached")

    report([
      {"oversized cached", false},
      {"small cached", true},
      {"ETS size", "#{Provider.size(name)} MB"}
    ])
  end

  # --- Scenario 5: TTL expiry -----------------------------------------------

  defp ttl_expiry_scenario() do
    header("5. TTL expiry — 10k keys with 1s TTL are swept")

    name = start_cache(:"#{@cache}_ttl", expiration_interval_seconds: 1)

    for i <- 1..10_000 do
      Provider.store(name, {"ttl_#{i}", 1}, {:ok, i})
    end

    count_before = Provider.count(name)
    Process.sleep(2_500)
    count_after = Provider.count(name)

    assert!(count_before >= 9_999, "expected ~10k entries, got #{count_before}")
    assert!(count_after == 0, "expected 0 entries after TTL sweep, got #{count_after}")

    report([
      {"entries before sweep", count_before},
      {"entries after sweep", count_after}
    ])
  end

  # --- Scenario 6: memory footprint at controlled hit ratios ------------------

  defp hit_ratio_scenario(ratio) do
    ops = env_int("BENCH_HITRATIO_OPS", 50_000)
    workers = env_int("BENCH_WORKERS", System.schedulers_online() * 4)
    hot_pool = 1_000
    pct = trunc(ratio * 100)

    header("6. Memory footprint — #{pct}% cache-hit ratio, #{ops} get_or_store calls")

    # max_entries far above what this scenario writes: we want the raw memory
    # footprint of the entries, without eviction interfering (scenario 2
    # already covers eviction).
    name = start_cache(:"#{@cache}_hits_#{pct}", max_entries: 500_000)

    miss_counter = :counters.new(1, [])

    # Pre-seed the hot pool so "hit" draws actually hit from the first op
    for i <- 1..hot_pool do
      Provider.store(name, {hot_key(i), 600}, payload(hot_key(i)))
    end

    :erlang.garbage_collect()
    mem_before = beam_mb()
    sampler = start_sampler(fn -> :erlang.memory(:total) end)
    ops_per_worker = div(ops, workers)

    {elapsed_ms, latencies} =
      time(fn ->
        1..workers
        |> Task.async_stream(
          fn _ -> hit_ratio_worker(name, ratio, hot_pool, miss_counter, ops_per_worker) end,
          max_concurrency: workers,
          timeout: :infinity
        )
        |> Enum.flat_map(fn {:ok, worker_latencies} -> worker_latencies end)
      end)

    peak_mem_mb = Float.round(stop_sampler(sampler) / (1024 * 1024), 1)

    # The worker Tasks are dead here; collect the remaining processes so the
    # settled number reflects what actually stays resident (mostly ETS).
    Enum.each(Process.list(), &:erlang.garbage_collect/1)
    mem_after = beam_mb()

    total_ops = length(latencies)
    misses = :counters.get(miss_counter, 1)
    measured_hit_ratio = 1.0 - misses / total_ops
    entries = Provider.count(name)
    ets_mb = Provider.size(name)
    bytes_per_entry = if entries > 0, do: trunc(ets_mb * 1024 * 1024 / entries), else: 0
    sorted = Enum.sort(latencies)

    assert!(
      abs(measured_hit_ratio - ratio) < 0.03,
      "measured hit ratio #{Float.round(measured_hit_ratio, 3)} deviates from target #{ratio}"
    )

    report([
      {"hit ratio target/measured", "#{pct}% / #{Float.round(measured_hit_ratio * 100, 1)}%"},
      {"ops (misses=computations)", "#{total_ops} (#{misses})"},
      {"throughput", "#{rate(total_ops, elapsed_ms)} ops/s"},
      {"latency p50", "#{percentile(sorted, 50)} µs"},
      {"latency p95", "#{percentile(sorted, 95)} µs"},
      {"latency p99", "#{percentile(sorted, 99)} µs"},
      {"entries", entries},
      {"ETS size", "#{ets_mb} MB (#{bytes_per_entry} B/entry)"},
      {"BEAM memory", "#{mem_before} MB → peak #{peak_mem_mb} MB → settled #{mem_after} MB"},
      {"wall time", "#{elapsed_ms} ms"}
    ])

    # Drop this scenario's cache so its ETS table does not skew the memory
    # numbers of the next hit-ratio run.
    stop_cache(name)
  end

  defp hit_ratio_worker(cache, ratio, hot_pool, miss_counter, ops) do
    for _ <- 1..ops do
      key =
        if :rand.uniform() < ratio do
          hot_key(:rand.uniform(hot_pool))
        else
          "miss_#{:erlang.unique_integer([:positive])}"
        end

      {us, _} =
        :timer.tc(fn ->
          Provider.get_or_store(
            cache,
            {key, 600},
            fn ->
              :counters.add(miss_counter, 1, 1)
              payload(key)
            end,
            & &1
          )
        end)

      us
    end
  end

  defp hot_key(i), do: "hot_#{i}"

  # A representative cached value: ~120 timeseries points, the shape most
  # getMetric resolvers produce. Gzipped term_to_binary lands at ~1-2kb,
  # matching typical production entries.
  defp payload(key) do
    base = ~U[2026-01-01 00:00:00Z]
    offset = :erlang.phash2(key, 1000)

    points =
      for i <- 1..120 do
        %{datetime: DateTime.add(base, i * 3600, :second), value: (i + offset) * 1.0}
      end

    {:ok, points}
  end

  # --- Scenario 7: parallel-friendliness ---------------------------------------
  #
  # The cache-miss path must not funnel work through any single process. This
  # scenario checks the three properties that distinguish our design from the
  # Cachex built-ins (Courier / Locksmith queue / Evented hook):
  #   a. the get_or_store fallback executes in the CALLER process,
  #   b. per-key lock throughput scales with workers on distinct keys
  #      (locks are plain ETS ops, no lock-server),
  #   c. no process in the system accumulates a mailbox under load
  #      (a GenServer bottleneck shows up here immediately).

  defp parallelism_scenario() do
    header("7. Parallel-friendliness — ETS lock path, no process bottleneck")

    name = start_cache(:"#{@cache}_par", [])

    # (a) fallback runs in the caller process
    parent = self()

    {:ok, _} =
      Provider.get_or_store(
        name,
        "ctx_check_key",
        fn ->
          send(parent, {:fallback_ran_in, self()})
          {:ok, 1}
        end,
        & &1
      )

    fallback_pid =
      receive do
        {:fallback_ran_in, pid} -> pid
      after
        1_000 -> raise "fallback did not report its pid"
      end

    assert!(
      fallback_pid == parent,
      "fallback ran in #{inspect(fallback_pid)}, caller is #{inspect(parent)} — " <>
        "a Courier/worker-based implementation regression"
    )

    # (b) distinct-key lock throughput: 1 worker vs N workers
    lock_ops = 50_000
    workers = System.schedulers_online()
    {ms_1, rate_1} = lock_run(name, 1, lock_ops)
    {ms_n, rate_n} = lock_run(name, workers, lock_ops)

    # (c) same-key contention: winners execute, losers return :locked instantly
    contenders = 16
    attempts_each = 2_000
    executed = :counters.new(1, [])
    locked = :counters.new(1, [])

    1..contenders
    |> Task.async_stream(
      fn _ ->
        for _ <- 1..attempts_each do
          case SanbaseWeb.Graphql.CachexKeyLock.try_with_lock(name, :contended_key, fn -> :ok end) do
            {:executed, :ok} -> :counters.add(executed, 1, 1)
            :locked -> :counters.add(locked, 1, 1)
          end
        end
      end,
      max_concurrency: contenders,
      timeout: :infinity
    )
    |> Stream.run()

    executed_count = :counters.get(executed, 1)
    locked_count = :counters.get(locked, 1)

    assert!(
      executed_count + locked_count == contenders * attempts_each,
      "lock attempts lost: #{executed_count} + #{locked_count} != #{contenders * attempts_each}"
    )

    assert!(executed_count > 0, "no lock attempt ever succeeded under contention")

    mailbox = max_mailbox()
    assert!(mailbox < 100, "a process accumulated a mailbox of #{mailbox} under lock load")

    locksmith_info = :ets.info(:cachex_locksmith)

    report([
      {"fallback process", "caller (#{inspect(fallback_pid)})"},
      {"distinct-key locks, 1 worker", "#{rate_1} locks/s (#{ms_1} ms)"},
      {"distinct-key locks, #{workers} workers", "#{rate_n} locks/s (#{ms_n} ms)"},
      {"same-key contention", "#{executed_count} executed / #{locked_count} rejected instantly"},
      {"max mailbox (any process)", mailbox},
      {"locksmith table leftover locks", Keyword.get(locksmith_info, :size)}
    ])
  end

  defp lock_run(cache, workers, total_ops) do
    ops_per_worker = div(total_ops, workers)

    {ms, _} =
      time(fn ->
        1..workers
        |> Task.async_stream(
          fn w ->
            for i <- 1..ops_per_worker do
              {:executed, :ok} =
                SanbaseWeb.Graphql.CachexKeyLock.try_with_lock(cache, {w, i}, fn -> :ok end)
            end
          end,
          max_concurrency: workers,
          timeout: :infinity
        )
        |> Stream.run()
      end)

    {ms, rate(total_ops, ms)}
  end

  # --- Helpers ----------------------------------------------------------------

  # Samples `sample_fun` every 25ms and reports the peak value on :stop.
  defp start_sampler(sample_fun) do
    parent = self()

    spawn_link(fn ->
      sample_loop(sample_fun, parent, 0)
    end)
  end

  defp sample_loop(sample_fun, parent, peak) do
    receive do
      :stop -> send(parent, {:peak, peak})
    after
      25 ->
        sample_loop(sample_fun, parent, max(peak, sample_fun.()))
    end
  end

  defp stop_sampler(pid) do
    send(pid, :stop)

    receive do
      {:peak, peak} -> peak
    after
      5_000 -> raise "sampler did not report"
    end
  end

  defp time(fun) do
    {us, result} = :timer.tc(fun)
    {div(us, 1000), result}
  end

  defp rate(_ops, 0), do: "n/a"
  defp rate(ops, ms), do: trunc(ops / ms * 1000)

  defp percentile([], _), do: 0

  defp percentile(sorted, p) do
    idx = min(length(sorted) - 1, trunc(length(sorted) * p / 100))
    Enum.at(sorted, idx)
  end

  defp beam_mb(), do: Float.round(:erlang.memory(:total) / (1024 * 1024), 1)

  defp max_mailbox() do
    Process.list()
    |> Enum.map(fn pid ->
      case Process.info(pid, :message_queue_len) do
        {:message_queue_len, len} -> len
        nil -> 0
      end
    end)
    |> Enum.max()
  end

  defp header(text) do
    IO.puts("\n--- #{text}")
  end

  defp report(rows) do
    Enum.each(rows, fn {label, value} ->
      IO.puts("    #{String.pad_trailing(to_string(label), 28)} #{value}")
    end)
  end

  defp assert!(true, _msg), do: :ok
  defp assert!(false, msg), do: raise("FAILED: #{msg}")
  defp env_int(name, default), do: (System.get_env(name) || "#{default}") |> String.to_integer()
end

CachexProviderBench.run()
