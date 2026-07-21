# GraphQL Caching: Architecture, Rationale and Testing Guide

This document covers the Cachex-backed GraphQL cache
(`SanbaseWeb.Graphql.CachexProvider` + `CachexKeyLock` + `CachexBoundEnforcer`):
why it is built the way it is, which Cachex built-ins were deliberately NOT
used (with reproducible evidence), and how to test the caching at every level.

## Architecture overview

`cache_resolve` (in `SanbaseWeb.Graphql.Cache`) wraps Absinthe resolvers with
per-field caching. The storage layer is Cachex 4.x, wrapped by
`SanbaseWeb.Graphql.CachexProvider` with three properties Cachex does not give
out of the box:

1. **Hard entry bound** (`SanbaseWeb.Graphql.CachexBoundEnforcer`) — inline
   size check on every write, single-flight async `Cachex.prune/3`
   coordinated via `:atomics`, and write-shedding past `1.1 × max_entries`.
2. **Caller-process cache-miss execution with stampede protection**
   (`SanbaseWeb.Graphql.CachexKeyLock`) — per-key locks on Cachex's own
   Locksmith ETS table; lock losers poll the cache and return as soon as the
   winner's value lands.
3. **Value hygiene** — gzip-compressed terms, `{:error, _}`/`{:nocache, _}`
   results never cached, entries whose compressed size exceeds 500kb never
   cached.

## Why not the Cachex built-ins?

### Why not `Cachex.fetch` (the Courier)?

`Cachex.fetch/3` provides stampede protection by dispatching every cache-miss
fallback through the cache's **Courier** — a single GenServer per cache that
runs each fallback in a spawned worker process. Two independent problems:

**1. It breaks Dataloader-based resolvers — silently.**

`Dataloader.Ecto` embeds the **calling process pid** into every batch key —
see `deps/dataloader/lib/dataloader/ecto.ex` (`get_keys/2`):

```elixir
{{:assoc, schema, self(), assoc_field, queryable, opts}, id, record}
```

The pid is there on purpose: when the batch later runs, it is passed to Ecto
as the `:caller` option (connection ownership — this is how the sandbox works
in tests). The consequence is that `Dataloader.load` and `Dataloader.get`
MUST run in the same process, and that process must be the one Absinthe uses
for resolution.

Under `Cachex.fetch`, the resolver (which calls `Dataloader.load`) runs in
Courier worker A, and the on-load callback (which calls `Dataloader.get`)
runs in Courier worker B. The batch key computed in worker B contains worker
B's pid, the results are stored under a key containing worker A's pid, the
lookup misses, `Dataloader.get` returns `nil`, and the callback either crashes
(`Enumerable not implemented for Atom ... nil`) or silently resolves the
field to `nil`. When it crashes, Cachex converts the raise into a
`%Cachex.Error{}` struct returned as a *value*, which Absinthe then rejects
with `Invalid value returned from resolver` — a whole-query 500.

Reproduced on commit `048a92bc7` (the fetch-based provider) by re-enabling
the dataloader-backed `marketSegment` field: both projects in the test
resolved to `nil`, with the crash stack showing the callback inside
`Cachex.Services.Courier.handle_call/3`. The same field and test pass with
the current caller-process provider.

**2. Cross-request state leakage through the Courier.**

The Courier deduplicates in-flight fallbacks per key: if request 2 asks for a
key while request 1's fallback is still running, request 2 is queued and
receives request 1's result (`deps/cachex/lib/cachex/services/courier.ex`).
For plain values this is exactly what you want. For resolvers returning
`{:middleware, Absinthe.Middleware.Dataloader, {loader, callback}}` tuples it
means request 2 receives **request 1's loader and callback closures** —
per-request state leaking across requests.

Additional smaller issues: process-dictionary signals set inside the fallback
(`:do_not_cache_query`, read by `AbsintheBeforeSend` to skip whole-document
caching) land in the worker's process dictionary and are lost; and every
cache miss serializes through one GenServer per cache.

### Why not `Cachex.transaction` (the Locksmith queue)?

`Cachex.transaction/3` executes its function inside the cache's single
**Locksmith Queue** GenServer (`deps/cachex/lib/cachex/services/locksmith/queue.ex`)
— same wrong-process problem as the Courier, plus every transaction in the
whole cache serializes through one process.

### What we DO use from the Locksmith

The Locksmith's *lock primitives* (as opposed to its transaction queue) are
plain ETS operations on a global lock table created with
`write_concurrency: true` — `lock/2` is `:ets.insert_new`, `unlock/2` is
`:ets.delete`, both executed by the calling process with no GenServer in the
path (~0.3–0.5µs per check, per Cachex's own comments).
`SanbaseWeb.Graphql.CachexKeyLock` drives these directly — the same approach
the Cachex v3 provider used in production for years — and adds a per-lock
guard process that releases the lock via owner-matched `:ets.delete_object`
if the holder is brutally killed (Cachex does not monitor lock owners).

### Why not the `Cachex.Limit.*` hooks (alone)?

Cachex 4 removed the v3 `:limit`/`:policy`/`:reclaim` options — they are
**silently ignored** (see the official migration guide:
<https://cachex.hexdocs.pm/migrating-to-v4.html>). This is what caused the
original OOM: the deployed 4.x upgrade passed the dead v3 options and ran
unbounded. The v4 replacements are hooks, and neither holds under burst:

- `Cachex.Limit.Scheduled` — timer-only; overshoot is
  `write_rate × frequency`, unbounded in principle.
- `Cachex.Limit.Evented` — one hook GenServer receives a message per write
  and prunes per message; when writes outpace pruning it falls behind. The
  benchmark measured **~8× the configured limit** (384k entries vs a 50k
  bound) under 32 burst writers.

`CachexBoundEnforcer` enforces the bound inline on the write path instead
(peak measured at 1.1× the bound under the same burst), with a low-frequency
`Scheduled` hook kept as a backstop.

## How to test the caching

### 1. Unit / regression tests (CI)

```bash
mix test test/sanbase_web/cache/
```

- `cachex_provider_test.exs` — provider behavior: get/store/get_or_store,
  TTL-tuple keys, error/nocache handling, concurrency (single computation per
  key, value sharing, error retry semantics), oversized-value rejection,
  eviction config. Includes two guard tests that fail if anyone reintroduces
  `Cachex.fetch`:
  - *"get_or_store runs the fallback in the caller process"*
  - *"get_or_store fallback observes the caller's process dictionary"*
- `cachex_bound_enforcer_test.exs` — bound registration, soft/hard limit
  reporting, async prune, convergence without further writes.

### 2. Provider benchmark (no DB, no app boot)

```bash
mix run --no-start load_test/scripts/cachex_provider_bench.exs
```

Asserts the OOM-incident invariants and prints a report per scenario:

1. **Stampede** — 500 concurrent callers, one computation.
2. **Bounded growth** — burst writes vs `max_entries`; asserts peak ≤ 1.5×
   the bound (an unbounded-cache regression shows up as peak ≈ total writes).
3. **Mixed load** — throughput + latency percentiles, 90% hot / 10% unique.
4. **Oversized values** — compressed > 500kb not cached.
5. **TTL expiry** — janitor sweep reclaims entries.
6. **Memory footprint at controlled hit ratios** — 90% / 50% / 10% hit
   ratios, reporting measured hit ratio, entries, ETS MB, bytes/entry and
   BEAM before/peak/settled memory.
7. **Parallel-friendliness** — lock throughput scaling on distinct keys,
   same-key contention behavior, and a max-mailbox scan across all processes
   (a Courier/GenServer bottleneck shows up as a growing mailbox; the
   ETS-based design shows 0).

Tunables: `BENCH_DURATION_MS`, `BENCH_WORKERS`, `BENCH_MAX_ENTRIES`,
`BENCH_HITRATIO_OPS`.

### 3. End-to-end k6 tests (real queries, running server)

See `load_test/README.md` for setup (`mix load_test.seed_projects`,
`mix load_test.setup`). Two scripts:

- `scripts/graphql_load_test.js` — realistic traffic mix.
- `scripts/cache_saturation_test.js` — controlled server-side cache hit
  ratio. "Pool" requests repeat a deterministic set of
  (metric, slug, window, interval) combinations → cache hits after warmup;
  "fresh" requests use per-request-unique time windows → guaranteed misses
  that keep inserting entries. Latency is reported separately per class:

```bash
cd load_test
k6 run --env HIT_RATIO=0.9 scripts/cache_saturation_test.js
k6 run --env HIT_RATIO=0.5 scripts/cache_saturation_test.js
k6 run --env HIT_RATIO=0.1 scripts/cache_saturation_test.js
```

Expect `pool_query_duration` ≪ `fresh_query_duration`; `graphql_errors`
below threshold; server memory bounded (watch below).

### 4. Observing the cache on a live node

`SanbaseWeb.Graphql.CacheMonitor` (started in `web`/`all` containers) logs a
stats line every minute:

```text
GraphQL cache stats: entries=152340 table_memory_mb=27.4 payload_mb=214.8
```

and doubles as the **byte-size bound**: when the payload exceeds
`max_payload_mb` (1024 in `application.ex`), it sweeps the oldest entries
(LRW — Cachex orders by the `:modified` timestamp, and since our entries are
written once, that is insertion order) until the payload is back under the
bound, logging a warning with before/after numbers. This complements the
entry-count bound (`CachexBoundEnforcer`, per-write): count alone cannot
express a memory bound when entry sizes vary, and the byte check needs the
O(n) walk, so it runs on the monitor's cadence instead of per-write.

How much goes per sweep: proportional to the overshoot —
`removed = entries − trunc(entries × max_bytes/payload × 0.9)`, so a payload
just over the bound sheds ~10% of entries, 1.1× over sheds ~18%, 2× over
sheds ~55%. With a 60s check cadence the first trigger is normally "just
over", making 10–20% the typical sweep. Expired entries are purged first and
credited against the quota. The sweep is deliberately uncapped so the bound
is restored within a single tick; see the `CacheMonitor` moduledoc for the
full reasoning and the uniform-entry-size assumption behind the target.

The same numbers on demand, from the server's IEx shell (works in prod via
remote console):

```elixir
SanbaseWeb.Graphql.Cache.count()          # entries, O(1)
SanbaseWeb.Graphql.Cache.size()           # ETS table MB (overhead only), O(1)
SanbaseWeb.Graphql.Cache.payload_bytes()  # true value bytes, O(n), on demand
:erlang.memory(:total)                    # whole-BEAM footprint
:erlang.memory(:binary)                   # binary heap (where the payloads live)
:ets.info(:cachex_locksmith)              # lock table (size ≈ in-flight cache misses)
```

What the numbers mean:

- `count()` is the OOM canary — it must plateau near `max_entries`
  (2M default); unbounded growth here is the failure signature.
- `size()` counts only per-entry table overhead (~190 B/entry). The gzipped
  values are refc binaries (>64 bytes) stored on the shared binary heap, NOT
  in the ETS table's memory accounting.
- `payload_bytes()` is the true footprint of cached values. It is an O(n)
  table walk (~40ms per 200k entries) — call it when needed, never from hot
  paths. An exact maintained counter is impossible: the janitor removes
  expired entries with `:ets.select_delete/2`, a native batch delete where
  the removed entries never surface in Elixir, so a counter has nothing to
  decrement from.

During a deploy of cache-related changes, watch pod RSS, `count()` and
`payload_bytes()` — all three must plateau instead of growing without bound.

## Benchmark: new implementation vs the Cachex 3.6 one it replaces

Identical scenarios, same machine, provider public API only
(the version-specific knobs left at parity):

| Scenario | Old (3.6) | New (4.1.1) |
|---|---|---|
| Stampede: 500 callers of one 50ms computation | 9,959 ms | 80 ms |
| Unique-miss throughput, 32 workers | 366k/s | 450k/s |
| Mixed-load throughput (90% hit / 10% miss) | 1.32M ops/s | 1.53M ops/s |
| Burst write peak vs a 50k entry bound | 400k (8×, pruned ~3s *after* the burst) | 55k (1.1×, bounded *during* the burst) |
| Memory footprint at 90/50/10% hit ratios | par | par, slightly faster |

Two v3 behaviors uncovered while benchmarking, both worth remembering:

- v3's stampede protection used capped exponential backoff, so 500 waiters
  took ~10 seconds to pick up a 50ms computation. The current implementation
  polls at an escalating 10→100ms interval instead.
- v3 silently ignored the top-level `policy:`/`reclaim:` options (only the
  integer `limit:` applied, with the default 0.1 reclaim) — the "Cachex
  ignores options it doesn't know" trap predates the v4 upgrade.
