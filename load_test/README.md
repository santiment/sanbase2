# Load Testing

Local load testing for the Sanbase GraphQL API using [k6](https://k6.io/).
Full documentation (env var reference, stage runbook, how hit-ratio and
response-size control works): [docs/load-testing.md](../docs/load-testing.md).

## Prerequisites

```bash
brew install k6
```

## Setup

All commands require the app's DB to be running.

```bash
# 1. Seed projects (contract addresses, github orgs)
mix load_test.seed_projects

# 2. Create users with API keys + Business Pro subscriptions (no rate limits)
mix load_test.setup --users 20 --no-rate-limits
```

## Run Tests

```bash
cd load_test

# Smoke test (2 VUs, 30s)
k6 run --env SCENARIO=smoke scripts/graphql_load_test.js

# Load test (20 VUs, 2min)
k6 run --env SCENARIO=load scripts/graphql_load_test.js

# Stress test (ramp to 50 VUs over 3min)
k6 run --env SCENARIO=stress scripts/graphql_load_test.js
```

Override the target URL:

```bash
k6 run --env SCENARIO=smoke --env BASE_URL=http://localhost:4000 scripts/graphql_load_test.js
```

## Cleanup

```bash
mix load_test.cleanup
```

Deletes all `*@sanload.test` users and removes the API keys JSON file.
Note: seeded projects are left in place (harmless in local dev).

## GraphQL Cache (Cachex) Benchmark

Standalone load test for `SanbaseWeb.Graphql.CachexProvider` — no DB, no app
boot; only `:cachex` is started. It asserts the invariants whose violation
caused the Cachex 4 OOM incident: bounded ETS growth under burst writes,
single-flight cache stampede protection, oversized-value rejection and TTL
sweeping. It also reports throughput, latency percentiles for mixed
read/write load, and memory footprint at controlled cache-hit ratios
(90% / 50% / 10%).

```bash
mix run --no-start load_test/scripts/cachex_provider_bench.exs

# Tunables
BENCH_DURATION_MS=10000 BENCH_WORKERS=64 BENCH_MAX_ENTRIES=100000 \
  mix run --no-start load_test/scripts/cachex_provider_bench.exs
```

## Cache Saturation E2E Test (k6)

End-to-end variant of the hit-ratio benchmark: fires real `getMetric`
timeseries queries with a controlled server-side cache hit ratio. "Pool"
requests repeat a fixed set of (metric, slug, window, interval) combinations
(cache hits after warmup); "fresh" requests use per-request-unique time
windows (guaranteed misses that keep inserting new cache entries). Latency is
reported separately per class (`pool_query_duration` vs
`fresh_query_duration`).

Response sizes are controlled too: `DATA_POINTS_PER_QUERY` (default `180,1000,3000`)
mixes requests of different approximate data-point counts. Each metric's
`minInterval` is fetched in `setup()`; the query uses that interval and
stretches the from/to window to hit the target, so cache entries of very
different sizes are inserted. Daily-only metrics cap at a 730-day window
(~730 points) — the finest possible for them. Requests are tagged with
`data_points`, so per-size latency is available via
`--summary-trend-stats` or tag filtering.

```bash
cd load_test

# The three canonical hit-ratio profiles
k6 run --env HIT_RATIO=0.9 scripts/cache_saturation_test.js
k6 run --env HIT_RATIO=0.5 scripts/cache_saturation_test.js
k6 run --env HIT_RATIO=0.1 scripts/cache_saturation_test.js

# More VUs / longer run, bigger hot pool
k6 run --env HIT_RATIO=0.5 --env SCENARIO=stress --env POOL_SIZE=2000 \
  scripts/cache_saturation_test.js

# Only big responses (~3000 points each)
k6 run --env HIT_RATIO=0.5 --env DATA_POINTS_PER_QUERY=3000 \
  scripts/cache_saturation_test.js
```

Note: the pool can hold at most `metrics × slugs × data_points_per_query` distinct
combinations (12 × 20 × 3 = 720 with the built-in lists); a larger
`POOL_SIZE` logs a warning and effectively caps there.

## Running Against Stage

The k6 scripts don't need the local DB or mix tasks — just an API key.
Pass it via `APIKEY` (comma-separate several) and point `BASE_URL` at stage:

```bash
cd load_test
export STAGE_APIKEY=...   # keep it out of shell history / the repo

# Controlled request rate (recommended for remote targets): RATE req/s for
# DURATION, WARMUP=1 primes the hot pool so hit ratio is accurate from the
# first iteration.
k6 run \
  --env BASE_URL=https://api-stage.santiment.net \
  --env APIKEY=$STAGE_APIKEY \
  --env SCENARIO=rate --env RATE=30 --env DURATION=5m \
  --env HIT_RATIO=0.5 --env WARMUP=1 \
  scripts/cache_saturation_test.js
```

Tips for stage runs:

- `SCENARIO=rate` (constant-arrival-rate) keeps req/s fixed regardless of
  response latency — start at 20–30 RPS and ramp up in later runs; the only
  remaining limits are the nginx per-IP ones.
- `HIT_RATIO` sets the pool/fresh request split. The server-side cache TTL
  for `timeseriesData` is 300s (+ up to 90s per-key offset), so on runs much
  longer than that, expired pool entries get transparently re-primed — the
  observed hit ratio sits slightly below `HIT_RATIO`.
- The cache key does not include the user, so one API key is enough for all
  VUs to collide on the same pool keys.
- `graphql_load_test.js` accepts the same `APIKEY`/`BASE_URL` envs if you
  want a realistic mixed-traffic run instead of controlled hit ratios.

While it runs, watch the server-side cache from the server's IEx shell:

```elixir
SanbaseWeb.Graphql.Cache.count()  # entries
SanbaseWeb.Graphql.Cache.size()   # ETS megabytes
:erlang.memory(:total)            # whole-BEAM footprint
```
