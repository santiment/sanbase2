# GraphQL Caching: How It Works and How to Test It

The GraphQL API caches resolver results per field: `cache_resolve` (in
`SanbaseWeb.Graphql.Cache`) wraps Absinthe resolvers, and the storage layer is
Cachex, wrapped by three small modules:

- `SanbaseWeb.Graphql.CachexProvider` — get/store/get_or_store on top of
  Cachex, value compression, TTLs
- `SanbaseWeb.Graphql.CachexBoundEnforcer` — hard entry-count bound
- `SanbaseWeb.Graphql.CacheMonitor` — stats logging + byte-size bound

The moduledocs carry the detailed design rationale (including why several
Cachex built-ins are deliberately not used); this document explains how the
current approach works and how to test and observe it.

## How it works

### Reads and writes

Values are stored as gzipped `term_to_binary` binaries. A cache key is either
a plain key (default TTL) or a `{key, ttl_seconds}` tuple (per-entry TTL).
Expired entries are invisible to reads immediately (`lazy: true`) and swept by
the Cachex janitor every 10s. Results that must not be cached never are:
`{:error, _}` tuples, `{:nocache, _}` tuples (which also set the
`:do_not_cache_query` process flag so `AbsintheBeforeSend` skips caching the
whole document), and values whose compressed size exceeds 500kb.

### Entry-count bound

Every write checks the ETS entry count inline (`CachexBoundEnforcer`):

- over `max_entries` → exactly one process (an `:atomics` flag decides) spawns
  an async `Cachex.prune/3`, evicting the oldest ~30%;
- over `1.1 × max_entries` → the write is shed. Dropping a cache write is
  always correct, and it keeps the bound hard even when writes outpace the
  pruner.

A low-frequency `Cachex.Limit.Scheduled` hook (30s) remains as a backstop.
The bench measures the effect: under a 32-writer burst the cache peaks at
1.1× the bound (the built-in hooks alone let it reach ~8× — see the
`CachexBoundEnforcer` moduledoc).

### Byte-size bound and monitoring

`CacheMonitor` (started in `web`/`all` containers) logs a stats line every
minute:

```text
GraphQL cache stats: entries=152340 table_memory_mb=27.4 payload_mb=214.8
```

When the payload exceeds `max_payload_mb`, it sweeps the oldest entries
(LRW; our entries are written once, so that is insertion order) back under
the bound and logs a warning with before/after numbers. The sweep is
proportional to the overshoot — just over the bound sheds ~10% of entries,
1.1× over ~18%, 2× over ~55% — and deliberately uncapped so one tick restores
the bound. Full sweep math: `CacheMonitor` moduledoc.

The two bounds are complementary: count is enforced per-write (cheap),
bytes per-minute (needs an O(n) walk).

### Stampede protection

A cache miss takes a per-key lock (`CachexKeyLock`, plain ETS operations on
Cachex's own Locksmith table — no process in the path) and runs the resolver
function **in the caller process**, which Absinthe resolvers require (their
state — Dataloader batching, process-dictionary signals — is process-scoped;
the `CachexKeyLock` moduledoc has the full analysis).

Lock losers do not queue: they poll the cache at an escalating 10→100ms
interval and return as soon as the winner's value lands. If the lock is still
held after 60s (a legitimately long computation), the waiter logs a warning
and computes the value itself without the lock — a duplicate computation,
never a user-facing error. Locks leaked by brutally-killed request processes
are released immediately by a per-lock guard process.

## Defaults

| Setting | Default | Where |
|---|---|---|
| `max_entries` | 50,000 | `CachexProvider` |
| `reclaim` on prune | 0.3 | `CachexProvider` |
| default TTL | 300s | `CachexProvider` |
| per-entry size cap | 500kb compressed | `CachexProvider` |
| `max_payload_mb` | 1024 | `CachexProvider.max_payload_mb/0` |
| lock poll interval | 10ms doubling to 100ms | `CachexProvider` |
| lock wait before computing without lock | 60s | `CachexProvider` |

All overridable per cache via the provider/monitor child opts.

## How to test the caching

### 1. Unit / regression tests (CI)

```bash
mix test test/sanbase_web/cache/
```

- `cachex_provider_test.exs` — get/store/get_or_store behavior, TTL-tuple
  keys, error/nocache handling, concurrency (single computation per key,
  value sharing, error retry semantics), oversized-value rejection, eviction
  config. Includes two guard tests that fail if cache-miss functions stop
  running in the caller process.
- `cachex_bound_enforcer_test.exs` — bound registration, soft/hard limit
  reporting, async prune, convergence without further writes.
- `cache_monitor_test.exs` — stats logging, byte-bound sweep (oldest entries
  evicted, newest survive), missing-table safety.

### 2. Provider benchmark (no DB, no app boot)

```bash
mix run --no-start load_test/scripts/cachex_provider_bench.exs
```

Asserts the cache's core invariants and prints a report per scenario:

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
   (a process bottleneck shows up as a growing mailbox; this design shows 0).

Tunables: `BENCH_DURATION_MS`, `BENCH_WORKERS`, `BENCH_MAX_ENTRIES`,
`BENCH_HITRATIO_OPS`. A comparison against the previous (Cachex 3.6)
implementation is in PR #5268.

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

## Observing the cache on a live node

From the server's IEx shell (works in prod via remote console):

```elixir
SanbaseWeb.Graphql.Cache.count()          # entries, O(1)
SanbaseWeb.Graphql.Cache.size()           # ETS table MB (overhead only), O(1)
SanbaseWeb.Graphql.Cache.payload_bytes()  # true value bytes, O(n), on demand
:erlang.memory(:total)                    # whole-BEAM footprint
:erlang.memory(:binary)                   # binary heap (where the payloads live)
:ets.info(:cachex_locksmith)              # lock table (size ≈ in-flight cache misses)
```

What the numbers mean:

- `count()` must plateau near `max_entries`; unbounded growth here is the
  OOM failure signature.
- `size()` counts only per-entry table overhead (~190 B/entry) — the gzipped
  values are refc binaries stored on the shared binary heap, outside the ETS
  table's memory accounting.
- `payload_bytes()` is the true footprint of cached values — an O(n) walk,
  on demand only (see `CachexProvider.payload_bytes/1` for why it cannot be
  a maintained counter).

During a deploy of cache-related changes, watch pod RSS, `count()` and
`payload_bytes()` — all three must plateau instead of growing without bound.
