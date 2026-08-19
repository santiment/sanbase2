defmodule Sanbase.Monitoring.MemDbg do
  @moduledoc """
  BEAM memory debugging toolkit for the remote console.

  Compiled into the release — from `bin/sanbase remote`:

      alias Sanbase.Monitoring.MemDbg
      MemDbg.report()          # one-shot snapshot of everything
      MemDbg.watch_spikes(300) # log any process whose heap crosses 300 MB,
                               # with a stacktrace naming the guilty code path

  Everything here is read-only except `bin_leak/1` (forces GC on all
  processes) and `watch_spikes/1` (starts a background watcher). NONE of
  these functions run automatically — the automatic per-minute sampling is
  done by `Sanbase.Monitoring.MemoryCollector`, which persists
  `Sanbase.Monitoring.MemoryStat` rows shown on the admin panel
  (`/admin/memory_stats`). Unattended trends therefore come from the DB;
  this module is for interactive digging when a trend looks wrong.

  ## Cost guide — safe vs heavy

  Cheap, callable any time: `overall/0`, `alloc/0`, `os/0`, `top_ets/1`,
  `top_msgq/1`, `atoms/0`, `snapshot/0`, `inspect_pid/1`.

  O(process count), fine interactively: `top_procs/1`, `by_name/1`.

  Heavy — use deliberately, prefer off-peak:

    * `top_bin/1` — `:binary` info returns every refc binary ref per
      process, O(total refs).
    * `bin_leak/1` — forces GC on EVERY process, real CPU spike.
    * `report/1` — includes both of the above.

  ## Manual snapshot / diff (same console session)

      s1 = MemDbg.snapshot()   # cheap, silent; returns a map
      # ... wait ...
      MemDbg.diff(s1, MemDbg.snapshot())  # what grew: buckets, ETS, process groups

  ## How memory is accounted — three layers

  The same RAM is counted three different ways, and the numbers legitimately
  disagree. Comparing the layers tells you what kind of problem you have.

  LAYER 1 — live Erlang terms: `:erlang.memory/0`, shown by `overall/0`.
  Counts bytes occupied by actual Erlang data: process heaps ("processes"),
  refc binaries ("binary"), ETS tables ("ets"), loaded code, atoms. This is
  what your code is responsible for: if a bucket here grows steadily you
  have a real leak — use `diff/2` / `top_*` to find it.

  LAYER 2 — allocator carriers: `alloc/0`. The VM's allocators grab big
  "carriers" from the OS (mmap) and place term "blocks" inside them:
  `used` = sum of blocks (~layer 1), `allocated` = sum of carriers (~what
  the OS actually gave the VM). Empty space inside carriers is invisible to
  layer 1 but is real RSS. Two ways it appears: the high-water ratchet (a
  spike forces many carriers; after the data dies the carriers stay for
  reuse — looks like a leak, is not) and fragmentation (long-lived blocks
  scattered across carriers keep them all alive at low "util"). Persistent
  low util on a big allocator is tunable with erl flags, e.g.
  `+MBas aobf +MBlmbcs 512` (binary) / `+MHas aobf +MHlmbcs 512` (heap).
  The VM releases empty carriers with MADV_FREE — the kernel keeps the pages
  charged to the container until memory pressure, so cgroup numbers can stay
  high even after carriers are logically freed.

  LAYER 3 — OS process + cgroup: `os/0`. What dashboards plot.
  `VmRSS` = physical RAM mapped now; `VmHWM` = peak RSS since start (never
  decreases — huge HWM with normal RSS = a past spike; catch the next one
  with `watch_spikes/1`). smaps: `Pss` is the truest single number (the JIT
  maps its code twice, double-counting ~code-size MB in Rss); `Anonymous` =
  heaps + carriers, the real app memory. cgroup v2: `memory.current` = the
  dashboard number = anon + file + kernel; `file` = page cache, reclaimable,
  NOT a leak; `shmem` = the JIT code memfd, constant; kubernetes
  working_set = memory.current - inactive_file.

  ## Leak-hunting playbook

  1. Slow rise over days: check the admin memory page / DB trend first.
     Which layer-1 bucket grows?
       * processes -> `top_procs/1` / `by_name/1`; a fat one -> `inspect_pid/1`
       * binary    -> `top_bin/1`, then `bin_leak/1`: if forced GC frees a
         lot, long-lived processes hold sub-binaries of big payloads. Fix:
         `:binary.copy/1` on the kept slice, or `{:fullsweep_after, N}`
         spawn opt / hibernate the hoarder.
       * ets       -> `top_ets/1`; rising row counts = cache without TTL/eviction
       * atoms     -> something converts input to atoms; find it and use
         `String.to_existing_atom/1`
     If no bucket grows but RSS does -> `alloc/0`: low util = fragmentation
     (VM flags), or compare with `os/0` — maybe the dashboard counts page
     cache ("file") and there is no BEAM problem at all.
  2. Spikes (VmHWM >> VmRSS): `watch_spikes(300)`; reports land in pod logs
     with a stacktrace. Then fix that code path (stream/paginate the big
     response).
  3. RSS far above `:erlang.memory(:total)`: `alloc/0` explains carrier
     overhead; `os/0` explains JIT double-count, MADV_FREE lag, and cgroup
     extras. Only what remains after those is native/NIF memory (OpenSSL etc.).
  """

  alias Sanbase.Monitoring.MemorySnapshot

  @watcher_name :memdbg_spike_watcher

  def report(n \\ 15) do
    overall()
    alloc()
    os()
    top_procs(n)
    by_name(n)
    top_bin(n)
    top_ets(n)
    top_msgq(5)
    atoms()
    :ok
  end

  # ---------------------------------------------------------------------------
  # Snapshot / diff
  # ---------------------------------------------------------------------------

  # Cheap point-in-time capture. Keep the returned map, diff two of them later.
  def snapshot() do
    %{
      taken_at: DateTime.utc_now(),
      erlang: Map.new(:erlang.memory()),
      rss_bytes: MemorySnapshot.rss_bytes(),
      proc_count: length(Process.list()),
      atom_count: :erlang.system_info(:atom_count),
      ets: ets_by_name(),
      procs: procs_by_name()
    }
  end

  def diff(old, new, n \\ 15) do
    minutes = DateTime.diff(new.taken_at, old.taken_at) / 60

    IO.puts("\n== Diff over #{Float.round(minutes, 1)} min ==")

    IO.puts("\nVM memory buckets:")

    for key <-
          Map.keys(new.erlang)
          |> Enum.sort_by(&(-abs(Map.get(new.erlang, &1, 0) - Map.get(old.erlang, &1, 0)))) do
      delta = Map.get(new.erlang, key, 0) - Map.get(old.erlang, key, 0)
      IO.puts("  #{pad(key, 18)} #{pad(mb(Map.get(new.erlang, key, 0)), 12)} #{mb_signed(delta)}")
    end

    case {old.rss_bytes, new.rss_bytes} do
      {a, b} when is_integer(a) and is_integer(b) ->
        IO.puts("\nOS RSS: #{mb(b)} (#{mb_signed(b - a)})")

      _ ->
        :ok
    end

    IO.puts(
      "processes: #{new.proc_count} (#{sign(new.proc_count - old.proc_count)}) " <>
        "atoms: #{new.atom_count} (#{sign(new.atom_count - old.atom_count)})"
    )

    print_deltas("Process groups (by name)", old.procs, new.procs, n)
    print_deltas("ETS tables", old.ets, new.ets, n)
    :ok
  end

  # ---------------------------------------------------------------------------
  # One-shot views
  # ---------------------------------------------------------------------------

  def overall() do
    IO.puts("\n== VM memory breakdown ==")

    mem = :erlang.memory()

    mem
    |> Enum.sort_by(fn {_k, v} -> -v end)
    |> Enum.each(fn {k, v} -> IO.puts("#{pad(k, 18)} #{mb(v)}") end)

    pt = :persistent_term.info()
    IO.puts("#{pad(:persistent_term, 18)} #{mb(pt.memory)} (#{pt.count} terms)")
    IO.puts("(if container RSS >> total: run alloc() and os() to see where the gap is)")
    mem[:total]
  end

  def top_procs(n \\ 15) do
    IO.puts("\n== Top #{n} processes by memory ==")

    each_proc([:memory, :message_queue_len, :current_function | MemorySnapshot.name_keys()])
    |> Enum.sort_by(fn {_pid, info} -> -info[:memory] end)
    |> Enum.take(n)
    |> Enum.each(fn {pid, info} ->
      IO.puts(
        "#{pad(inspect(pid), 15)} #{pad(mb(info[:memory]), 12)} msgq=#{pad(info[:message_queue_len], 6)} " <>
          "#{pad(MemorySnapshot.name_from_info(info), 45)} cur=#{fmt_mfa(info[:current_function])}"
      )
    end)
  end

  # Total memory per process name. One process at 50 MB shows up in top_procs;
  # ten thousand at 50 KB only show up here.
  def by_name(n \\ 15) do
    IO.puts("\n== Top #{n} process groups by total memory ==")

    procs_by_name()
    |> Enum.sort_by(fn {_name, {_count, bytes}} -> -bytes end)
    |> Enum.take(n)
    |> Enum.each(fn {name, {count, bytes}} ->
      IO.puts("#{pad(mb(bytes), 12)} count=#{pad(count, 8)} #{name}")
    end)
  end

  # Off-heap refc binaries referenced by each process. A long-lived process holding many
  # or large refc binaries (often sub-binaries of big HTTP/DB responses) is the classic
  # slow-rise leak. Shared binaries count once per referencing process, so the sum can
  # exceed :erlang.memory(:binary). HEAVY: O(total binary refs) - do not automate.
  def top_bin(n \\ 15) do
    IO.puts("\n== Top #{n} processes by referenced refc binaries ==")

    each_proc([:binary | MemorySnapshot.name_keys()])
    |> Enum.map(fn {pid, info} -> {pid, info, bin_bytes(info[:binary])} end)
    |> Enum.sort_by(fn {_pid, _info, bytes} -> -bytes end)
    |> Enum.take(n)
    |> Enum.each(fn {pid, info, bytes} ->
      IO.puts(
        "#{pad(inspect(pid), 15)} #{pad(mb(bytes), 12)} bins=#{pad(length(info[:binary]), 8)} " <>
          MemorySnapshot.name_from_info(info)
      )
    end)
  end

  def top_ets(n \\ 15) do
    IO.puts("\n== Top #{n} ETS tables by memory ==")

    MemorySnapshot.top_ets(n)
    |> Enum.each(fn %{name: name, memory_bytes: bytes, rows: rows, owner: owner} ->
      IO.puts("#{pad(name, 45)} #{pad(mb(bytes), 12)} rows=#{pad(rows, 10)} owner=#{owner}")
    end)
  end

  def top_msgq(n \\ 10) do
    IO.puts("\n== Top #{n} processes by message queue ==")

    rows =
      each_proc([:message_queue_len | MemorySnapshot.name_keys()])
      |> Enum.filter(fn {_pid, info} -> info[:message_queue_len] > 0 end)
      |> Enum.sort_by(fn {_pid, info} -> -info[:message_queue_len] end)
      |> Enum.take(n)

    if rows == [] do
      IO.puts("(all queues empty)")
    else
      Enum.each(rows, fn {pid, info} ->
        IO.puts(
          "#{pad(inspect(pid), 15)} msgq=#{pad(info[:message_queue_len], 8)} " <>
            MemorySnapshot.name_from_info(info)
        )
      end)
    end
  end

  def atoms() do
    count = :erlang.system_info(:atom_count)
    limit = :erlang.system_info(:atom_limit)
    IO.puts("\n== Atoms ==\n#{count} / #{limit} (#{Float.round(count / limit * 100, 1)}%)")
  end

  # Deep-dive one process. Accepts a pid or a pasted string: "#PID<0.123.0>" / "<0.123.0>".
  def inspect_pid(pid_string) when is_binary(pid_string) do
    pid_string
    |> String.replace_prefix("#PID", "")
    |> String.to_charlist()
    |> :erlang.list_to_pid()
    |> inspect_pid()
  rescue
    _ -> IO.puts("cannot parse pid from #{inspect(pid_string)}")
  end

  def inspect_pid(pid) when is_pid(pid) do
    keys = [
      :memory,
      :message_queue_len,
      :total_heap_size,
      :heap_size,
      :stack_size,
      :reductions,
      :status,
      :current_function,
      :current_stacktrace,
      :garbage_collection,
      :binary,
      :dictionary,
      :registered_name,
      :initial_call
    ]

    case Process.info(pid, keys) do
      nil ->
        IO.puts("#{inspect(pid)} is dead")

      info ->
        word_size = :erlang.system_info(:wordsize)
        gc = info[:garbage_collection] || []

        IO.puts("""

        == #{inspect(pid)} #{MemorySnapshot.name_from_info(info)} ==
        memory           #{mb(info[:memory])}
        total_heap       #{mb(info[:total_heap_size] * word_size)} (heap #{mb(info[:heap_size] * word_size)}, stack #{mb(info[:stack_size] * word_size)})
        refc binaries    #{mb(bin_bytes(info[:binary]))} in #{length(info[:binary] || [])} refs
        msgq             #{info[:message_queue_len]}
        status           #{info[:status]}   reductions #{info[:reductions]}
        fullsweep_after  #{gc[:fullsweep_after]}   minor_gcs #{gc[:minor_gcs]}
        initial_call     #{fmt_mfa(info[:dictionary][:"$initial_call"] || info[:initial_call])}
        ancestors        #{inspect(info[:dictionary][:"$ancestors"])}
        current          #{fmt_mfa(info[:current_function])}
        """)

        IO.puts("stacktrace:")

        info[:current_stacktrace]
        |> List.wrap()
        |> Enum.take(8)
        |> Enum.each(fn entry -> IO.puts("  " <> Exception.format_stacktrace_entry(entry)) end)
    end

    :ok
  end

  # ---------------------------------------------------------------------------
  # Active experiments
  # ---------------------------------------------------------------------------

  # recon-style bin_leak: GC everything, then see how much memory drops and who was
  # hoarding binary refs. Big binary drop = processes keeping refc binaries alive (fix:
  # :binary.copy/1 on the kept slice, or {:fullsweep_after, N} / hibernate for the
  # hoarder). Big processes drop = lazily-GC'd garbage inflating RSS between collections.
  # HEAVY + side effects (forces GC on every process) - never automate.
  def bin_leak(n \\ 15) do
    IO.puts("\n== bin_leak: GC all processes ==")
    before_bin = :erlang.memory(:binary)
    before_procs = :erlang.memory(:processes)

    deltas =
      Enum.flat_map(Process.list(), fn pid ->
        with {:binary, before_bins} <- Process.info(pid, :binary),
             true <- :erlang.garbage_collect(pid),
             {:binary, after_bins} <- Process.info(pid, :binary) do
          [
            {pid, bin_bytes(before_bins) - bin_bytes(after_bins),
             length(before_bins) - length(after_bins)}
          ]
        else
          _ -> []
        end
      end)

    IO.puts("binary memory:    #{mb(before_bin)} -> #{mb(:erlang.memory(:binary))}")
    IO.puts("processes memory: #{mb(before_procs)} -> #{mb(:erlang.memory(:processes))}")
    IO.puts("top #{n} binary droppers:")

    deltas
    |> Enum.sort_by(fn {_pid, bytes, _count} -> -bytes end)
    |> Enum.take(n)
    |> Enum.each(fn {pid, bytes, count} ->
      IO.puts(
        "#{pad(inspect(pid), 15)} freed=#{pad(mb(bytes), 12)} refs=#{pad(count, 8)} " <>
          MemorySnapshot.proc_name(pid)
      )
    end)
  end

  # Catch what causes memory spikes: reports any process whose heap grows past
  # threshold_mb (fires on GC events via :erlang.system_monitor - cheap). Output goes to
  # the console and Logger, so spikes land in pod logs after you detach. One watcher per
  # node; calling again replaces it, as it replaces any other :erlang.system_monitor user.
  def watch_spikes(threshold_mb \\ 200) do
    stop_watch()
    words = div(threshold_mb * 1_048_576, :erlang.system_info(:wordsize))

    pid =
      spawn(fn ->
        # detach from the remote console group leader so IO from crashes
        # cannot take us down after the console disconnects
        with user when is_pid(user) <- Process.whereis(:user) do
          Process.group_leader(self(), user)
        end

        watch_loop(%{})
      end)

    Process.register(pid, @watcher_name)
    :erlang.system_monitor(pid, [{:large_heap, words}])

    IO.puts(
      "watching for process heaps > #{threshold_mb} MB, reports go to pod logs " <>
        "(MemDbg.stop_watch() to stop)"
    )

    :ok
  end

  def stop_watch() do
    if Process.whereis(@watcher_name), do: :erlang.system_monitor(:undefined)
    kill_registered(@watcher_name)
  end

  # ---------------------------------------------------------------------------
  # OS / allocator views
  # ---------------------------------------------------------------------------

  # OS/cgroup view from inside the container: is the dashboard number the beam process
  # RSS, or RSS + page cache? cgroup "file" = page cache from files written/read in the
  # container - reclaimable, not a leak, but counted by container_memory_usage_bytes and
  # (its active part) by working_set.
  def os() do
    IO.puts("\n== OS view (inside container) ==")
    os_pid = System.pid()

    print_file_lines(
      "/proc/#{os_pid}/status",
      ~r/^(VmRSS|VmHWM|VmSwap|Threads)/,
      "beam process status",
      &format_kb_line/1
    )

    print_file_lines(
      "/proc/#{os_pid}/smaps_rollup",
      ~r/^(Rss|Pss|Anonymous|Shared_Clean|Shared_Dirty|Private_Clean|Private_Dirty|Swap)\b/,
      "beam smaps_rollup",
      &format_kb_line/1
    )

    # cgroup v2, then v1
    case File.read("/sys/fs/cgroup/memory.current") do
      {:ok, bytes} ->
        IO.puts("\ncgroup v2 memory.current: #{mb(String.to_integer(String.trim(bytes)))}")

        print_file_lines(
          "/sys/fs/cgroup/memory.stat",
          ~r/^(anon|file|kernel|kernel_stack|slab|sock|shmem|file_mapped|inactive_file|active_file|inactive_anon|active_anon)\s/,
          "cgroup v2 memory.stat",
          &format_stat_line/1
        )

      _ ->
        case File.read("/sys/fs/cgroup/memory/memory.usage_in_bytes") do
          {:ok, bytes} ->
            IO.puts("\ncgroup v1 usage_in_bytes: #{mb(String.to_integer(String.trim(bytes)))}")

            print_file_lines(
              "/sys/fs/cgroup/memory/memory.stat",
              ~r/^(cache|rss|rss_huge|mapped_file|swap|inactive_file|active_file|inactive_anon|active_anon)\s/,
              "cgroup v1 memory.stat",
              &format_stat_line/1
            )

          _ ->
            IO.puts("no cgroup memory files found")
        end
    end

    IO.puts("""

    interpretation:
      VmRSS               = beam process memory as the OS sees it (JIT dual-maps
                            code, so this can overstate by ~code size; Pss is truer)
      cgroup anon (rss)   = process memory charged to the pod
      cgroup file (cache) = page cache from container file IO - reclaimable
      dashboard usage     ~= anon + file (+ kernel); working_set = usage - inactive_file
      If file/cache is big -> the "rise" is cache, not a BEAM leak.
    """)

    :ok
  end

  # Per-allocator: "allocated" = carrier sizes (what the OS gave the VM, ~RSS), "used" =
  # block sizes (what live Erlang data occupies, ~:erlang.memory). Big unused on
  # eheap_alloc/binary_alloc = carriers ratcheted up by past spikes or fragmentation.
  def alloc() do
    IO.puts("\n== Allocator carriers vs blocks ==")

    rows =
      MemorySnapshot.allocator_rows()
      |> Enum.sort_by(fn {_name, used, allocated} -> used - allocated end)

    IO.puts(
      "#{pad("allocator", 22)} #{pad("used", 12)} #{pad("allocated", 12)} #{pad("unused", 12)} util"
    )

    Enum.each(rows, fn {name, used, allocated} ->
      util = if allocated > 0, do: "#{round(used / allocated * 100)}%", else: "-"

      IO.puts(
        "#{pad(name, 22)} #{pad(mb(used), 12)} #{pad(mb(allocated), 12)} " <>
          "#{pad(mb(allocated - used), 12)} #{util}"
      )
    end)

    total_used = rows |> Enum.map(fn {_, u, _} -> u end) |> Enum.sum()
    total_alloc = rows |> Enum.map(fn {_, _, a} -> a end) |> Enum.sum()

    IO.puts(
      "\n#{pad("TOTAL", 22)} #{pad(mb(total_used), 12)} #{pad(mb(total_alloc), 12)} " <>
        "#{pad(mb(total_alloc - total_used), 12)} #{round(total_used / max(total_alloc, 1) * 100)}%"
    )

    IO.puts("""

    interpretation:
      allocated ~= what BEAM holds from the OS (should be close to RSS,
                   minus code/atom/shared-libs overhead of ~100-150 MB)
      unused    ~= carrier space with no live data: spike high-water + fragmentation
    """)

    :ok
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp each_proc(keys) do
    Enum.flat_map(Process.list(), fn pid ->
      case Process.info(pid, keys) do
        nil -> []
        info -> [{pid, info}]
      end
    end)
  end

  # full (not top-N) maps of %{name => {count, bytes}}, for diff/2
  defp procs_by_name() do
    each_proc([:memory | MemorySnapshot.name_keys()])
    |> Enum.group_by(fn {_pid, info} -> MemorySnapshot.name_from_info(info) end)
    |> Map.new(fn {name, group} ->
      {name,
       {length(group), group |> Enum.map(fn {_pid, info} -> info[:memory] end) |> Enum.sum()}}
    end)
  end

  defp ets_by_name() do
    word_size = :erlang.system_info(:wordsize)

    :ets.all()
    |> Enum.flat_map(fn table ->
      case MemorySnapshot.safe_ets_info(table, :memory) do
        mem when is_integer(mem) ->
          [{inspect(MemorySnapshot.safe_ets_info(table, :name)), mem * word_size}]

        _ ->
          []
      end
    end)
    |> Enum.group_by(fn {name, _} -> name end, fn {_, bytes} -> bytes end)
    |> Map.new(fn {name, sizes} -> {name, {length(sizes), Enum.sum(sizes)}} end)
  end

  # entries: %{name => {count, bytes}}; prints top n by absolute byte delta
  defp print_deltas(title, old, new, n) do
    IO.puts("\n#{title} (top #{n} by change):")

    rows =
      Map.keys(old)
      |> Enum.concat(Map.keys(new))
      |> Enum.uniq()
      |> Enum.map(fn name ->
        {old_count, old_bytes} = Map.get(old, name, {0, 0})
        {new_count, new_bytes} = Map.get(new, name, {0, 0})
        {name, new_bytes - old_bytes, new_count - old_count, new_bytes, new_count}
      end)
      |> Enum.reject(fn {_, bytes_delta, count_delta, _, _} ->
        abs(bytes_delta) < 102_400 and count_delta == 0
      end)
      |> Enum.sort_by(fn {_, bytes_delta, _, _, _} -> -abs(bytes_delta) end)
      |> Enum.take(n)

    if rows == [] do
      IO.puts("  (no meaningful changes)")
    else
      Enum.each(rows, fn {name, bytes_delta, count_delta, new_bytes, new_count} ->
        IO.puts(
          "  #{pad(mb_signed(bytes_delta), 12)} count#{pad(sign(count_delta), 7)} " <>
            "now=#{pad(mb(new_bytes), 12)} n=#{pad(new_count, 7)} #{name}"
        )
      end)
    end
  end

  defp watch_loop(last_seen) do
    receive do
      {:monitor, pid, :large_heap, info} ->
        now = System.monotonic_time(:second)

        # throttle: one report per pid per 30s (large_heap fires on every GC)
        last = Map.get(last_seen, pid)

        last_seen =
          if last == nil or now - last >= 30 do
            report_spike(pid, info)
            Map.put(last_seen, pid, now)
          else
            last_seen
          end

        # keep the throttle map bounded
        last_seen =
          if map_size(last_seen) > 500 do
            Map.filter(last_seen, fn {_pid, t} -> now - t < 60 end)
          else
            last_seen
          end

        watch_loop(last_seen)

      _other ->
        watch_loop(last_seen)
    end
  end

  defp report_spike(pid, info) do
    word_size = :erlang.system_info(:wordsize)

    heap_bytes =
      ((info[:heap_block_size] || 0) + (info[:old_heap_block_size] || 0) +
         (info[:mbuf_size] || 0)) * word_size

    details =
      case Process.info(
             pid,
             [:current_function, :current_stacktrace, :message_queue_len, :memory] ++
               MemorySnapshot.name_keys()
           ) do
        nil ->
          "process already dead"

        proc_info ->
          stack =
            proc_info[:current_stacktrace]
            |> List.wrap()
            |> Enum.take(4)
            |> Enum.map_join("\n    ", &Exception.format_stacktrace_entry/1)

          "name=#{MemorySnapshot.name_from_info(proc_info)} cur=#{fmt_mfa(proc_info[:current_function])} " <>
            "msgq=#{proc_info[:message_queue_len]} proc_mem=#{mb(proc_info[:memory])}\n    #{stack}"
      end

    msg = "[MemDbg] large heap #{mb(heap_bytes)} on #{inspect(pid)} #{details}"
    IO.puts(msg)
    safe_log(msg)
  end

  # kill and wait for the name to actually free up, so an immediate restart
  # can re-register without racing the async exit
  defp kill_registered(name) do
    case Process.whereis(name) do
      nil ->
        :ok

      pid ->
        ref = Process.monitor(pid)
        Process.exit(pid, :kill)

        receive do
          {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
        after
          1_000 -> :ok
        end
    end
  end

  defp safe_log(msg) do
    Logger.bare_log(:warning, msg)
  rescue
    _ -> :ok
  end

  defp print_file_lines(path, regex, label, formatter) do
    case File.read(path) do
      {:ok, content} ->
        IO.puts("\n#{label} (#{path}):")

        content
        |> String.split("\n")
        |> Enum.filter(&Regex.match?(regex, &1))
        |> Enum.each(fn line -> IO.puts("  " <> formatter.(line)) end)

      _ ->
        IO.puts("\n#{label}: #{path} not readable")
    end
  end

  # /proc lines are "Name:   12345 kB" - convert to MB
  defp format_kb_line(line) do
    case Regex.run(~r/^(\S+):\s+(\d+) kB$/, line) do
      [_, name, kb] -> "#{pad(name, 18)} #{mb(String.to_integer(kb) * 1024)}"
      _ -> line
    end
  end

  # cgroup stat lines are "name <bytes>" - append human-readable MB
  defp format_stat_line(line) do
    case String.split(line) do
      [name, value] ->
        case Integer.parse(value) do
          {bytes, ""} -> "#{pad(name, 18)} #{mb(bytes)}"
          _ -> line
        end

      _ ->
        line
    end
  end

  defp bin_bytes(bins) when is_list(bins),
    do: bins |> Enum.map(fn {_ref, size, _refc} -> size end) |> Enum.sum()

  defp bin_bytes(_), do: 0

  defp fmt_mfa(mfa), do: MemorySnapshot.fmt_mfa(mfa)

  defp mb(bytes) when is_integer(bytes), do: "#{Float.round(bytes / 1_048_576, 2)} MB"

  defp mb_signed(bytes) when bytes >= 0, do: "+" <> mb(bytes)
  defp mb_signed(bytes), do: mb(bytes)

  defp sign(n) when n >= 0, do: "+#{n}"
  defp sign(n), do: "#{n}"

  defp pad(term, n), do: String.pad_trailing(to_string_safe(term), n)

  defp to_string_safe(term) when is_binary(term), do: term
  defp to_string_safe(term) when is_atom(term) or is_integer(term), do: to_string(term)
  defp to_string_safe(term), do: inspect(term)
end
