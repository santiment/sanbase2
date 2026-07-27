# Memory Monitoring

Two independent tools answer two different questions:

| Question | Tool |
| --- | --- |
| Is memory growing, on which pod, since when? | `/admin/memory_stats` (fed by the collector) |
| Which process/table/binary is holding it right now? | `Sanbase.Monitoring.MemDbg` in `bin/sanbase remote` |

The dashboard is unattended and historical. `MemDbg` is interactive and
live-only — it is what you reach for once the dashboard tells you *where* to
look.

## The collector

`Sanbase.Monitoring.MemoryCollector` is a GenServer started on every pod
regardless of container type. Once a minute it writes one
`Sanbase.Monitoring.MemoryStat` row describing that pod, into the
`node_memory_stats` Postgres table. There is no cross-pod coordination:
each pod reports itself.

What one row holds:

* OS level — `rss_bytes`, `rss_hwm_bytes` (read from `/proc`, so `nil` on
  macOS dev machines)
* allocator level — `alloc_used_bytes` (blocks), `alloc_allocated_bytes`
  (carriers)
* VM level — `vm_total_bytes` and the processes / binary / ETS / code buckets
* counters — `process_count`, `atom_count`
* `details` (JSONB) — top ETS tables by memory, plus a process-group
  breakdown collected only on every 5th sample because it is O(process count)

Sampling runs inside a short-lived, unlinked `Task`, so garbage produced
while measuring dies with the task instead of accumulating in the
collector's own heap, and a failed sample never takes the collector down.

`pod_name` comes from `HOSTNAME`. Deployment pods get a fresh name on every
rollout, so `pod_name` identifies a pod *incarnation*, not a stable series;
`container_type` is the stable grouping dimension. For StatefulSet pods
(`sanbase-web-N`) the name survives restarts, so one BEAM lifetime is
identified by `(pod_name, beam_started_at)` — the dashboard uses that pair
so that a restart, which resets memory, never shows up as a drop in a trend.

### Configuration

| Env var | Default | Meaning |
| --- | --- | --- |
| `MEMORY_COLLECTOR_ENABLED` | `true` | Set to `false`/`0` to stop sampling on that pod |
| `MEMORY_COLLECTOR_RETENTION_DAYS` | `90` | Rows older than this are deleted |

Both are read through `config :sanbase, Sanbase.Monitoring.MemoryCollector`
in `config/config.exs`. Unparseable values are logged and ignored rather
than obeyed: an unrecognized `MEMORY_COLLECTOR_ENABLED` keeps collection
**on** (silently losing fleet-wide monitoring is the worse failure), and an
unusable retention value falls back to 90 days.

The collector is disabled in `config/test.exs` — tests call the modules
directly.

### Retention and volume

Every 60th tick (so roughly hourly) a pod deletes rows older than the
retention window, in batches of 10k ids to avoid one statement locking a
large row range. The delete is idempotent, so all pods running it
concurrently is fine.

At 7 pods × 1 row/minute × 90 days that is ~907k rows. A real row measured
locally costs ~2.3 KB all-in (heap tuple + the JSONB `details` + both
indexes), so expect **~2–3 GB** for the full window. Most of that is
`details`; shorten the retention window if the table becomes a problem.

## The dashboard — `/admin/memory_stats`

Admin-panel-viewer role required, same gating as the other admin LiveViews.
Read-only, auto-refreshes every minute.

* **Live pods** — pods that reported in the last 5 minutes, with their latest
  sample. Pods that reported earlier but not recently show up under "Known
  pods, not reporting now" with their first/last snapshot times, which is
  how you find a replaced deployment pod's history before it is pruned.
* **Overview chart** — one metric across all live pods. The metric badges
  combine (except `Process count`, which cannot share an axis with bytes and
  is therefore exclusive). Window: 1h … 7d.
* **Per-pod chart**, three modes:
  * *Buckets* — where live data sits (processes / binary / ETS).
  * *Layers (leak vs ratchet)* — RSS high-water, RSS, carriers, blocks and VM
    total on one axis. The gaps between the lines name the cause: allocated −
    used is carrier slack (spike ratchet or fragmentation, not a leak);
    RSS − allocated is native/NIF memory the VM cannot see; RSS converging
    toward a flat early high-water means a past spike, not a leak.
  * *Alloc utilization %* — blocks / carriers. Falling utilization while RSS
    rises is fragmentation, not growing live data.
* **Window stats** — min/avg/max and a smoothed trend over the current BEAM
  incarnation, plus the two derived components (carrier slack, native/other).
  The trend compares the average of the newest ~10% of samples against the
  oldest ~10%, so a single spike does not read as a trend.

A sample that recorded no value for a metric stays in the series as a gap,
so the chart breaks the line instead of drawing a straight line through an
outage. Long windows are bucketed in Postgres rather than fetched raw, and
each bucket keeps its **peak** — a minute-long spike is exactly what someone
opens this page to find, and a stride-based downsample would be free to skip
it.

## MemDbg — interactive digging

`Sanbase.Monitoring.MemDbg` is compiled into the release and never runs on
its own. From `bin/sanbase remote`:

```elixir
alias Sanbase.Monitoring.MemDbg

MemDbg.report()           # one-shot snapshot of everything
MemDbg.overall()          # :erlang.memory/0 buckets
MemDbg.alloc()            # allocator carriers vs blocks, per allocator
MemDbg.os()               # VmRSS / VmHWM / smaps / cgroup numbers
MemDbg.top_procs(15)      # fattest processes
MemDbg.by_name(15)        # grouped by registered name / initial call
MemDbg.top_ets(15)
MemDbg.top_msgq(10)       # longest message queues
MemDbg.inspect_pid("#PID<0.123.0>")
MemDbg.watch_spikes(300)  # log any process crossing 300 MB, with a stacktrace
MemDbg.stop_watch()
```

Snapshot and diff within one console session:

```elixir
s1 = MemDbg.snapshot()
# ... wait ...
MemDbg.diff(s1, MemDbg.snapshot())
```

**Cost.** Everything above is cheap except three: `top_bin/1` walks every
refc binary ref on every process, `bin_leak/1` forces GC on *every* process
(a real CPU spike), and `report/1` includes both. Use them deliberately and
prefer off-peak. Everything else is read-only and safe to call any time.

The module's `@moduledoc` carries the full three-layer accounting
explanation and a leak-hunting playbook — read it in the console with
`h Sanbase.Monitoring.MemDbg`.
