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

From the server's IEx shell (works in prod via remote console):

```elixir
SanbaseWeb.Graphql.Cache.count()   # number of entries
SanbaseWeb.Graphql.Cache.size()    # ETS megabytes
:erlang.memory(:total)             # whole-BEAM footprint
:ets.info(:cachex_locksmith)       # lock table (size ≈ in-flight cache misses)
```

During a deploy of cache-related changes, watch pod RSS and
`Cache.count()` — the count must plateau near `max_entries` (2M default,
tunable via the provider's `:max_entries` opt) instead of growing without
bound, and RSS must plateau with it.
